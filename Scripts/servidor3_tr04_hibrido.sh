#!/bin/bash

# ====================================================================
# Script de Automação - SERVIDOR 3 (TR = 0.4) — HÍBRIDO + LOG + CENÁRIOS
# - Um SEED por CENÁRIO (mapeamento 1:1): rotas_${ve}_${scenario}_mod.rou.xml
# - Barra de progresso com 2 casas
# - Registra tempos separados: first_seconds e second_seconds (+ wall)
# - Busca robusta do .add.xml (com _mod / sem _mod / glob)
# - Copia .add.xml para nome com _seed<seed> (não sobrescreve)
# - CSV consolidado por execução
# - Tuning: inotify/polling para esperar .add.xml
# - THREADS auto via nproc
# ====================================================================

set -euo pipefail
ulimit -n 65535 || true
export PYTHONHASHSEED=0

# ------------------- Tuning da espera do .add.xml -------------------
USE_INOTIFY=0   # 1 = usar inotifywait (se disponível); 0 = polling
POLL_SEC=1      # intervalo entre checagens (s) no modo polling
POLL_MAX=900    # tempo máximo de espera (s) pelo .add.xml (15 min)

# LOG/TRAP
LOG_DIR="./logs"; mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/servidor3_$(date +%Y%m%d_%H%M%S).log"
trap 'echo "[SERVIDOR_3] Falha na linha $LINENO: \"$BASH_COMMAND\" (status $?)" | tee -a "$LOG_FILE"' ERR

# ------------------- Parâmetros -------------------
ERS=(10 20 30)
VES=(5 10 20)
TRS=(0.4)
METHODS=("random" "greedy" "grasp")

# CENÁRIOS e SEEDS 1:1  (mesmo comprimento)
SCENARIOS=(0 1 2 3 4)                 # usa rotas_${ve}_${scenario}_mod.rou.xml
SEEDS=(2025 2026 2027 2028 2029)      # seed de mesmo índice do cenário

# THREADS automático pela máquina, com possibilidade de sobrescrever por env
THREADS=${THREADS:-$(nproc)}

CAPACITY=5
SERVER_ID="SERVIDOR_3"
MAX_PARALLEL_METHODS=1   # 1=serial | 2/3=parcial/total

# Saídas
OUTPUT_DIR="./output_servidor3"
RESULTS_DIR="./results_servidor3"
CSV_FILE="./results_servidor3_metrics.csv"
mkdir -p "$OUTPUT_DIR" "$RESULTS_DIR"

# ------------------- Funções de log -------------------
timestamp () { date "+%Y-%m-%d %H:%M:%S"; }
log () { echo "[$(timestamp)] $*" | tee -a "$LOG_FILE"; }

# ------------------- Checagens rápidas (não abortam) -------------------
if (( ${#SCENARIOS[@]} != ${#SEEDS[@]} )); then
  echo "[$SERVER_ID] ERRO: SCENARIOS e SEEDS devem ter o MESMO tamanho. SCENARIOS=${#SCENARIOS[@]} SEEDS=${#SEEDS[@]}" | tee -a "$LOG_FILE"
  exit 1
fi
missing=()
for m in shapely numpy pandas networkx sumolib traci; do
  python3 -c "import $m" >/dev/null 2>&1 || missing+=("$m")
done
(( ${#missing[@]} )) && { log "AVISO: faltam módulos Python: ${missing[*]}"; log "Sugestão: python3 -m pip install ${missing[*]}"; }
command -v sumo >/dev/null 2>&1 || log "AVISO: 'sumo' não encontrado no PATH; verifique SUMO_HOME."
(( USE_INOTIFY==1 )) && command -v inotifywait >/dev/null 2>&1 || true

# ------------------- Acumular tempos p/ resumo -------------------
RANDOM_TIMES_FILE=$(mktemp)
GREEDY_TIMES_FILE=$(mktemp)
GRASP_TIMES_FILE=$(mktemp)
trap 'rm -f "$RANDOM_TIMES_FILE" "$GREEDY_TIMES_FILE" "$GRASP_TIMES_FILE"' EXIT

# ------------------- Utilitários -------------------
format_time () {
  local T=$1
  printf "%02d:%02d:%02d" $((T/3600)) $(( (T%3600)/60 )) $((T%60))
}

PROG_BAR_WIDTH=50
TOTAL_TASKS=0
COMPLETED_TASKS=0
SCRIPT_START_TIME=$(date +%s)

init_progress () {
  TOTAL_TASKS=$1
  COMPLETED_TASKS=0
  echo "[$SERVER_ID] Progresso total (execuções): 0/$TOTAL_TASKS"
  log  "Progresso total (execuções): 0/$TOTAL_TASKS"
}

tick_progress () {
  COMPLETED_TASKS=$((COMPLETED_TASKS+1))
  local elapsed=$(( $(date +%s) - SCRIPT_START_TIME ))

  # porcentagem com 2 casas decimais
  local pct_dec
  pct_dec=$(awk "BEGIN { if ($TOTAL_TASKS>0) printf \"%.2f\", ($COMPLETED_TASKS*100.0/$TOTAL_TASKS); else print \"0.00\" }")

  # barra proporcional (usa parte inteira para preencher)
  local pct_int=${pct_dec%.*}
  local filled_len=$(( PROG_BAR_WIDTH * pct_int / 100 ))
  (( filled_len > PROG_BAR_WIDTH )) && filled_len=$PROG_BAR_WIDTH
  local empty_len=$(( PROG_BAR_WIDTH - filled_len ))
  printf -v filled "%${filled_len}s" ""; filled=${filled// /#}
  printf -v empty  "%${empty_len}s" ""; empty=${empty// /-}

  local eta="--:--:--"
  if (( COMPLETED_TASKS > 0 )); then
    local avg=$(( elapsed / COMPLETED_TASKS ))
    local remain=$(( TOTAL_TASKS - COMPLETED_TASKS ))
    eta=$(format_time $(( avg * remain )))
  fi

  # console (barra dinâmica com % em 2 casas)
  printf "\r[%s] [%s%s] %6s%%  (%d/%d)  Elapsed: %s  ETA: %s" \
    "$SERVER_ID" "$filled" "$empty" "$pct_dec" "$COMPLETED_TASKS" "$TOTAL_TASKS" \
    "$(format_time "$elapsed")" "$eta"

  # registro persistente (linha fixa)
  echo "[$(timestamp)] PROGRESSO: ${pct_dec}% (${COMPLETED_TASKS}/${TOTAL_TASKS}) Elapsed=$(format_time "$elapsed") ETA=$eta" >> "$LOG_FILE"
}

# ------------------- Espera pelo .add.xml (inotify/polling) -------------------
wait_for_add () {
  local add_with_mod="$1"   # caminho candidato com _mod
  local add_no_mod="$2"     # caminho candidato sem _mod
  local method="$3"
  local ve="$4"
  local er="$5"

  local found=""
  if (( USE_INOTIFY==1 )) && command -v inotifywait >/dev/null 2>&1; then
    local end_at=$(( $(date +%s) + POLL_MAX ))
    while [[ -z "$found" && $(date +%s) -lt $end_at ]]; do
      inotifywait -qq -t "$POLL_SEC" -e create -e close_write "$OUTPUT_DIR" || true
      if [[ -f "$add_with_mod" ]]; then
        found="$add_with_mod"
      elif [[ -f "$add_no_mod" ]]; then
        found="$add_no_mod"
      else
        local GLOB_CAND
        GLOB_CAND=(${OUTPUT_DIR}/parking_areas_${method}_rotas_${ve}_0*_er${er}.add.xml)
        [[ -f "${GLOB_CAND[0]:-}" ]] && found="${GLOB_CAND[0]}"
      fi
    done
  else
    local waited=0
    while [[ -z "$found" && $waited -lt $POLL_MAX ]]; do
      if [[ -f "$add_with_mod" ]]; then
        found="$add_with_mod"
      elif [[ -f "$add_no_mod" ]]; then
        found="$add_no_mod"
      else
        local GLOB_CAND
        GLOB_CAND=(${OUTPUT_DIR}/parking_areas_${method}_rotas_${ve}_0*_er${er}.add.xml)
        [[ -f "${GLOB_CAND[0]:-}" ]] && found="${GLOB_CAND[0]}"
      fi
      [[ -n "$found" ]] || { sleep "$POLL_SEC"; waited=$((waited+POLL_SEC)); }
    done
  fi
  [[ -n "$found" ]] && echo "$found" || echo ""
}

# ------------------- Execução de uma simulação (método) -------------------
# args: er ve tr method scenario seed
run_simulation_for_method() {
  local er=$1 ve=$2 tr=$3 method=$4 scenario=$5 seed=$6

  local ROUTE_FILE="rotas_${ve}_${scenario}_mod.rou.xml"
  local scenario_tag="${ROUTE_FILE%.rou.xml}"      # ex: rotas_5_0_mod
  local scenario_tag_nomod="${scenario_tag%_mod}"  # ex: rotas_5_0

  local RESULT_DIR="${RESULTS_DIR}/ER${er}_VE${ve}_TR${tr}/${method}/scenario_${scenario}_seed_${seed}"
  mkdir -p "$RESULT_DIR"

  local LOG_FIRST="${RESULT_DIR}/${method}_first_run.log"
  local LOG_SECOND="${RESULT_DIR}/${method}_second_run.log"

  # Candidatos SEM seed (como o controlador grava)
  local ADD_WITH_MOD="${OUTPUT_DIR}/parking_areas_${method}_${scenario_tag}_er${er}.add.xml"
  local ADD_NO_MOD="${OUTPUT_DIR}/parking_areas_${method}_${scenario_tag_nomod}_er${er}.add.xml"

  local ADD_PATH_WITHSEED=""

  log "Iniciando: ER=$er, VE=$ve, TR=$tr, Método=$method, Cenário=${scenario}, Seed=$seed"

  # --- first_run (mede tempo até o .add.xml copiado com seed) ---
  local t0 t1 t2
  t0=$(date +%s)

  # checa existência de rota
  if [[ ! -f "$ROUTE_FILE" ]]; then
    log "ERRO: arquivo de rotas não encontrado: $ROUTE_FILE"
    exit 1
  fi

  rm -f "$ADD_WITH_MOD" "$ADD_NO_MOD" 2>/dev/null || true
  python3 controlador_pa_opt.py \
      --route_file "$ROUTE_FILE" --method "$method" --mode "first_run" \
      --er "$er" --capacity "$CAPACITY" --seed "$seed" \
      --out_dir "$OUTPUT_DIR" > "$LOG_FIRST" 2>&1

  # Espera o .add.xml aparecer (inotify ou polling)
  local FOUND_ADD=""
  FOUND_ADD=$(wait_for_add "$ADD_WITH_MOD" "$ADD_NO_MOD" "$method" "$ve" "$er")

  if [[ -z "$FOUND_ADD" ]]; then
    log "ERRO: .add.xml não encontrado. Tentado:"
    log "  - $ADD_WITH_MOD"
    log "  - $ADD_NO_MOD"
    log "  - ${OUTPUT_DIR}/parking_areas_${method}_rotas_${ve}_0*_er${er}.add.xml"
    exit 1
  fi

  # copia .add para versão com seed (mantendo cp)
  local BASE_FOUND; BASE_FOUND="$(basename "$FOUND_ADD" .add.xml)"
  ADD_PATH_WITHSEED="${OUTPUT_DIR}/${BASE_FOUND}_seed${seed}.add.xml"
  cp -f "$FOUND_ADD" "$ADD_PATH_WITHSEED"
  log "ADD encontrado: $(basename "$FOUND_ADD"); copiado para: $(basename "$ADD_PATH_WITHSEED")"

  t1=$(date +%s)
  local first_seconds=$((t1 - t0))

  # --- second_run (mede tempo isolado) ---
  python3 controlador_pa_opt.py \
      --route_file "$ROUTE_FILE" --method "$method" --mode "second_run" \
      --seed "$seed" --add_file "$ADD_PATH_WITHSEED" --tr_min "$tr" \
      --threads "$THREADS" --er "$er" --rep "$scenario" \
      --out_dir "$OUTPUT_DIR" > "$LOG_SECOND" 2>&1

  t2=$(date +%s)
  local second_seconds=$((t2 - t1))
  local wall_seconds=$((t2 - t0))

  case $method in
    random) echo "$wall_seconds" >> "$RANDOM_TIMES_FILE" ;;
    greedy) echo "$wall_seconds" >> "$GREEDY_TIMES_FILE" ;;
    grasp)  echo "$wall_seconds" >> "$GRASP_TIMES_FILE" ;;
  esac

  # Métricas do .add.xml
  local n_stations total_cap
  IFS=, read -r n_stations total_cap < <(python3 - "$ADD_PATH_WITHSEED" <<'PY'
import sys, xml.etree.ElementTree as ET
p = sys.argv[1]
root = ET.parse(p).getroot()
n=0; cap=0
for pa in root.findall(".//parkingArea"):
    n += 1
    c = pa.attrib.get("roadsideCapacity") or pa.attrib.get("capacity") or "0"
    try:
        cap += int(c)
    except:
        pass
print(f"{n},{cap}")
PY
  )

  # escreve CSV (sim_index guarda o ÍNDICE DO CENÁRIO)
  echo "${er},${ve},${tr},${ROUTE_FILE},${method},${seed},${scenario},${wall_seconds},${first_seconds},${second_seconds},${n_stations},${total_cap},$(basename "$ADD_PATH_WITHSEED")" >> "$CSV_FILE"

  log "Concluído: ER=$er, VE=$ve, TR=$tr, Método=$method, Cenário=${scenario}, Seed=$seed (Wall=${wall_seconds}s; First=${first_seconds}s; Second=${second_seconds}s; Estações=${n_stations}; Capacidade=${total_cap})"
}

# ------------------- Cabeçalho -------------------
echo "======================================================================"
echo "[$SERVER_ID] Iniciando Automação — $(date)"
echo "======================================================================"
echo "ER: ${ERS[*]} | VE: ${VES[*]} | TR(h): ${TRS[*]} | Métodos: ${METHODS[*]}"
echo "Cenários: ${SCENARIOS[*]} | Seeds: ${SEEDS[*]} (mapeamento 1:1)"
echo "Threads: $THREADS | MAX_PARALLEL_METHODS: $MAX_PARALLEL_METHODS"
echo "Saídas: OUTPUT_DIR=$OUTPUT_DIR , RESULTS_DIR=$RESULTS_DIR"
echo "CSV: $CSV_FILE"
echo "Log: $LOG_FILE"
echo "======================================================================"

log  "Iniciando Automação"
log  "ER=${ERS[*]} | VE=${VES[*]} | TR(h)=${TRS[*]} | Métodos=${METHODS[*]}"
log  "Cenários=${SCENARIOS[*]} | Seeds=${SEEDS[*]} (1:1)"
log  "Threads=$THREADS | MAX_PARALLEL_METHODS=$MAX_PARALLEL_METHODS"
log  "Saídas: OUTPUT_DIR=$OUTPUT_DIR ; RESULTS_DIR=$RESULTS_DIR ; CSV=$CSV_FILE ; LOG=$LOG_FILE"
log  "Tuning: USE_INOTIFY=$USE_INOTIFY | POLL_SEC=$POLL_SEC | POLL_MAX=$POLL_MAX"

# Verifica rotas exigidas
for ve in "${VES[@]}"; do
  for scenario in "${SCENARIOS[@]}"; do
    rf="rotas_${ve}_${scenario}_mod.rou.xml"
    [[ -f "$rf" ]] || { log "ERRO: arquivo de rotas não encontrado: $rf"; exit 1; }
  done
done

# CSV consolidado (cabeçalho atualizado)
echo "er,ve,tr,route_file,method,seed,sim_index,wall_seconds,first_seconds,second_seconds,n_stations,total_capacity,add_file" > "$CSV_FILE"
log  "CSV inicializado em $CSV_FILE"

# ------------------- Progresso: total de EXECUÇÕES -------------------
TOTAL_COMBINATIONS=$((${#ERS[@]} * ${#VES[@]} * ${#TRS[@]} * ${#SCENARIOS[@]} * ${#METHODS[@]}))
init_progress "$TOTAL_COMBINATIONS"

# ------------------- Loop Principal (HÍBRIDO; cenário ↔ seed 1:1) -------------------
# Requer Bash 5+ para 'wait -n'
for er in "${ERS[@]}"; do
  for ve in "${VES[@]}"; do
    for tr in "${TRS[@]}"; do

      # percorre cenários e sua seed correspondente
      for idx in "${!SCENARIOS[@]}"; do
        scenario="${SCENARIOS[$idx]}"
        seed="${SEEDS[$idx]}"

        # Lança métodos até o limite; conforme terminam, dispara os próximos
        declare -a remaining_methods=("${METHODS[@]}")
        declare -i running=0

        wait_one_and_tick () {
          if wait -n; then
            tick_progress
          else
            echo >> "$LOG_FILE"
            log "ERRO CRÍTICO: Um processo filho falhou. Abortando."
            exit 1
          fi
        }

        # Dispara os primeiros até o limite
        while (( running < MAX_PARALLEL_METHODS && ${#remaining_methods[@]} > 0 )); do
          method="${remaining_methods[0]}"; remaining_methods=("${remaining_methods[@]:1}")
          run_simulation_for_method "$er" "$ve" "$tr" "$method" "$scenario" "$seed" &
          running=$((running+1))
        done

        # Enquanto houver métodos restantes, espere terminar 1 e lance o próximo
        while (( ${#remaining_methods[@]} > 0 )); do
          wait_one_and_tick
          running=$((running-1))
          method="${remaining_methods[0]}"; remaining_methods=("${remaining_methods[@]:1}")
          run_simulation_for_method "$er" "$ve" "$tr" "$method" "$scenario" "$seed" &
          running=$((running+1))
        done

        # Aguarde os restantes em execução
        while (( running > 0 )); do
          wait_one_and_tick
          running=$((running-1))
        done

      done
    done
  done
done

# Linha nova após a barra
echo
log "Todas as execuções terminaram. Gerando resumo..."

# ------------------- Resumo Final -------------------
SCRIPT_END_TIME=$(date +%s)
TOTAL_SCRIPT_TIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))

echo "======================================================================"
echo "[$SERVER_ID] Todas as execuções concluídas."
echo "[$SERVER_ID] Tempo total: $(format_time "$TOTAL_SCRIPT_TIME")"
echo "CSV consolidado: $CSV_FILE"
echo "======================================================================"

log  "Execuções concluídas. Tempo total: $(format_time "$TOTAL_SCRIPT_TIME")"
log  "CSV consolidado salvo em: $CSV_FILE"

SUMMARY_FILE="./resumo_servidor3_hibrido_multiseed.txt"
{
  echo "======================================================================"
  echo "RESUMO (HÍBRIDO MULTI-CENÁRIO/SEED 1:1) - $SERVER_ID - $(date)"
  echo "======================================================================"
  echo "ERs: ${ERS[*]} | VEs: ${VES[*]} | TRs(h): ${TRS[*]} | Métodos: ${METHODS[*]}"
  echo "Cenários: ${SCENARIOS[*]} | Seeds: ${SEEDS[*]} (1:1) | Threads: $THREADS | Máx. paralelos: $MAX_PARALLEL_METHODS"
  echo "Tempo total: $(format_time "$TOTAL_SCRIPT_TIME")"
  echo "CSV: $CSV_FILE"
  echo
  printf "%-10s | %-8s | %-12s | %-15s | %-12s | %-12s\n" "Método" "Exec." "Tempo Total" "Médio/Exec" "Mín." "Máx."
  printf "%-10s-+-%-8s-+-%-12s-+-%-15s-+-%-12s-+-%-12s\n" "----------" "--------" "------------" "---------------" "------------" "------------"
  for method in "${METHODS[@]}"; do
    case $method in
      random) tf="$RANDOM_TIMES_FILE" ;;
      greedy) tf="$GREEDY_TIMES_FILE" ;;
      grasp)  tf="$GRASP_TIMES_FILE" ;;
    esac
    read -r count total avg min max <<< "$(awk '{s+=$1; if(NR==1||$1<mn)mn=$1; if(NR==1||$1>mx)mx=$1} END{if(NR>0)printf "%d %d %.2f %d %d\n", NR, s, s/NR, mn, mx; else print "0 0 0 0 0"}' "$tf")"
    if [[ "$count" -gt 0 ]]; then
      printf "%-10s | %-8d | %-12d | %-15.2f | %-12d | %-12d\n" \
        "$method" "$count" "$total" "$avg" "$min" "$max"
    else
      printf "%-10s | %-8s | %-12s | %-15s | %-12s | %-12s\n" \
        "$method" "0" "N/A" "N/A" "N/A" "N/A"
    fi
  done
} > "$SUMMARY_FILE"

log "Resumo salvo em: $SUMMARY_FILE"
log "Finalizado com sucesso."

