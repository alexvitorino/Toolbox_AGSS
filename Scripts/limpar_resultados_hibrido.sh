#!/bin/bash

# ====================================================================
# Script de Limpeza - Versão Híbrida Multi-Cenário/Seed
# Remove todos os resultados, logs e arquivos gerados pelos scripts híbridos
# ====================================================================

# --- Configuração de Cores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Funções de Output ---
print_header() {
    echo -e "${BOLD}${BLUE}======================================================================"
    echo -e "$1"
    echo -e "======================================================================${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCESSO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

print_question() {
    echo -e "${CYAN}[PERGUNTA]${NC} $1"
}

# --- Cabeçalho ---
print_header "Script de Limpeza - Versão Híbrida Multi-Cenário/Seed"
echo
print_info "Este script remove TODOS os resultados, logs e arquivos gerados"
print_info "pelos scripts híbridos de automação de simulações."
echo

# --- Detectar Estrutura de Arquivos ---
print_info "Detectando estrutura de arquivos..."

# Diretórios e arquivos da versão híbrida
DIRS_TO_CLEAN=(
    "./logs"
    "./results_servidor1"
    "./results_servidor2" 
    "./results_servidor3"
    "./output_servidor1"
    "./output_servidor2"
    "./output_servidor3"
)

FILES_TO_CLEAN=(
    "./results_servidor1_metrics.csv"
    "./results_servidor2_metrics.csv"
    "./results_servidor3_metrics.csv"
    "./resumo_servidor1_hibrido_multiseed.txt"
    "./resumo_servidor2_hibrido_multiseed.txt"
    "./resumo_servidor3_hibrido_multiseed.txt"
    "./resultados_execucoes_consolidado.csv"
    "./backup_csvs_*"
)

# Padrões de arquivos temporários
TEMP_PATTERNS=(
    "./parking_areas_*.add.xml"
    "./lane_visits_*.pkl"
    "./edges_*.txt"
    "./*.log"
    "./tripinfo*.xml"
    "./summary*.xml"
    "./fcd*.xml"
    "./detector*.xml"
)

# --- Verificação de Existência ---
FOUND_DIRS=()
FOUND_FILES=()
FOUND_TEMPS=()

echo
print_info "Verificando arquivos e diretórios existentes..."

# Verificar diretórios
for dir in "${DIRS_TO_CLEAN[@]}"; do
    if [ -d "$dir" ]; then
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        files=$(find "$dir" -type f 2>/dev/null | wc -l)
        print_success "✓ Diretório encontrado: $dir ($size, $files arquivos)"
        FOUND_DIRS+=("$dir")
    fi
done

# Verificar arquivos específicos
for file in "${FILES_TO_CLEAN[@]}"; do
    if [[ "$file" == *"*"* ]]; then
        # Padrão com wildcard
        matches=($(ls $file 2>/dev/null))
        if [ ${#matches[@]} -gt 0 ]; then
            for match in "${matches[@]}"; do
                if [ -f "$match" ]; then
                    size=$(ls -lh "$match" | awk '{print $5}')
                    print_success "✓ Arquivo encontrado: $match ($size)"
                    FOUND_FILES+=("$match")
                fi
            done
        fi
    else
        # Arquivo específico
        if [ -f "$file" ]; then
            size=$(ls -lh "$file" | awk '{print $5}')
            print_success "✓ Arquivo encontrado: $file ($size)"
            FOUND_FILES+=("$file")
        fi
    fi
done

# Verificar arquivos temporários
for pattern in "${TEMP_PATTERNS[@]}"; do
    matches=($(ls $pattern 2>/dev/null))
    if [ ${#matches[@]} -gt 0 ]; then
        for match in "${matches[@]}"; do
            if [ -f "$match" ]; then
                size=$(ls -lh "$match" | awk '{print $5}')
                print_warning "⚠ Arquivo temporário: $match ($size)"
                FOUND_TEMPS+=("$match")
            fi
        done
    fi
done

echo

# --- Resumo do que será removido ---
TOTAL_ITEMS=$((${#FOUND_DIRS[@]} + ${#FOUND_FILES[@]} + ${#FOUND_TEMPS[@]}))

if [ $TOTAL_ITEMS -eq 0 ]; then
    print_info "Nenhum arquivo ou diretório de resultados encontrado."
    print_success "O ambiente já está limpo!"
    exit 0
fi

print_warning "RESUMO DO QUE SERÁ REMOVIDO:"
echo

if [ ${#FOUND_DIRS[@]} -gt 0 ]; then
    print_warning "📁 Diretórios (${#FOUND_DIRS[@]}):"
    for dir in "${FOUND_DIRS[@]}"; do
        echo "   - $dir"
    done
    echo
fi

if [ ${#FOUND_FILES[@]} -gt 0 ]; then
    print_warning "📄 Arquivos (${#FOUND_FILES[@]}):"
    for file in "${FOUND_FILES[@]}"; do
        echo "   - $file"
    done
    echo
fi

if [ ${#FOUND_TEMPS[@]} -gt 0 ]; then
    print_warning "🗑️ Arquivos temporários (${#FOUND_TEMPS[@]}):"
    for temp in "${FOUND_TEMPS[@]}"; do
        echo "   - $temp"
    done
    echo
fi

print_warning "Total de itens a serem removidos: $TOTAL_ITEMS"
echo

# --- Confirmação ---
print_question "Tem certeza que deseja remover TODOS estes arquivos e diretórios?"
print_warning "Esta ação é IRREVERSÍVEL!"
echo
read -p "Digite 'CONFIRMAR' para prosseguir ou qualquer outra coisa para cancelar: " -r
echo

if [[ $REPLY != "CONFIRMAR" ]]; then
    print_info "Operação cancelada pelo usuário."
    print_success "Nenhum arquivo foi removido."
    exit 0
fi

# --- Processo de Limpeza ---
print_info "Iniciando processo de limpeza..."
echo

REMOVED_COUNT=0
FAILED_COUNT=0

# Remover diretórios
for dir in "${FOUND_DIRS[@]}"; do
    print_info "Removendo diretório: $dir"
    if rm -rf "$dir" 2>/dev/null; then
        print_success "  ✓ Removido com sucesso"
        REMOVED_COUNT=$((REMOVED_COUNT + 1))
    else
        print_error "  ✗ Falha na remoção"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

# Remover arquivos específicos
for file in "${FOUND_FILES[@]}"; do
    print_info "Removendo arquivo: $file"
    if rm -f "$file" 2>/dev/null; then
        print_success "  ✓ Removido com sucesso"
        REMOVED_COUNT=$((REMOVED_COUNT + 1))
    else
        print_error "  ✗ Falha na remoção"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

# Remover arquivos temporários
for temp in "${FOUND_TEMPS[@]}"; do
    print_info "Removendo temporário: $temp"
    if rm -f "$temp" 2>/dev/null; then
        print_success "  ✓ Removido com sucesso"
        REMOVED_COUNT=$((REMOVED_COUNT + 1))
    else
        print_error "  ✗ Falha na remoção"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

echo

# --- Limpeza Adicional ---
print_info "Executando limpeza adicional..."

# Remover arquivos de lock/pid se existirem
find . -name "*.lock" -o -name "*.pid" 2>/dev/null | while read -r lockfile; do
    if [ -f "$lockfile" ]; then
        print_info "Removendo lock: $lockfile"
        rm -f "$lockfile"
    fi
done

# Limpar cache Python se existir
if [ -d "./__pycache__" ]; then
    print_info "Removendo cache Python"
    rm -rf "./__pycache__"
fi

# Limpar arquivos de core dump
find . -name "core.*" -type f 2>/dev/null | while read -r corefile; do
    if [ -f "$corefile" ]; then
        print_info "Removendo core dump: $corefile"
        rm -f "$corefile"
    fi
done

echo

# --- Verificação Final ---
print_info "Verificando limpeza..."

REMAINING_ITEMS=0
for dir in "${DIRS_TO_CLEAN[@]}"; do
    [ -d "$dir" ] && REMAINING_ITEMS=$((REMAINING_ITEMS + 1))
done

for file in "${FILES_TO_CLEAN[@]}"; do
    if [[ "$file" == *"*"* ]]; then
        matches=($(ls $file 2>/dev/null))
        REMAINING_ITEMS=$((REMAINING_ITEMS + ${#matches[@]}))
    else
        [ -f "$file" ] && REMAINING_ITEMS=$((REMAINING_ITEMS + 1))
    fi
done

echo

# --- Relatório Final ---
print_header "Relatório de Limpeza"
echo
print_success "✓ Itens removidos com sucesso: $REMOVED_COUNT"
if [ $FAILED_COUNT -gt 0 ]; then
    print_error "✗ Falhas na remoção: $FAILED_COUNT"
fi
if [ $REMAINING_ITEMS -gt 0 ]; then
    print_warning "⚠ Itens restantes: $REMAINING_ITEMS"
else
    print_success "🎉 Limpeza completa! Nenhum item restante."
fi

echo
if [ $REMAINING_ITEMS -eq 0 ] && [ $FAILED_COUNT -eq 0 ]; then
    print_success "Ambiente completamente limpo e pronto para novas simulações!"
else
    print_warning "Alguns itens podem não ter sido removidos. Verifique as permissões."
fi

echo
print_info "Para executar novas simulações, use:"
print_info "  ./servidor1_tr01_hibrido.sh"
print_info "  ./servidor2_tr02_hibrido.sh"
print_info "  ./servidor3_tr04_hibrido.sh"
echo

