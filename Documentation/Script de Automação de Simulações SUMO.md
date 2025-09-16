# Script de Automação de Simulações SUMO - `servidor2_tr02_hibrido.sh`

## 1. Visão Geral

O script `servidor2_tr02_hibrido.sh` é uma ferramenta de automação robusta projetada para orquestrar uma série de simulações de tráfego usando o SUMO (Simulation of Urban MObility). Ele foi desenvolvido para executar experimentos complexos, variando múltiplos parâmetros, gerenciando a execução paralela de simulações e consolidando os resultados de forma organizada.

O principal objetivo do script é avaliar o desempenho de diferentes heurísticas de alocação de postos de recarga para veículos elétricos (VEs) em diversos cenários. Ele automatiza todo o fluxo de trabalho, desde a execução da simulação inicial para coleta de dados até a execução da simulação final com os postos de recarga alocados, medindo e registrando métricas de desempenho chave.

Este documento serve como um guia completo para entender, configurar e utilizar o script.

## 2. Funcionalidades Principais

-   **Execução em Lote**: Automatiza a execução de centenas de combinações de simulações, iterando sobre diferentes parâmetros como número de estações de recarga (ERs), porcentagem de veículos elétricos (VEs), tempo de recarga (TRs) e heurísticas de alocação.
-   **Mapeamento Cenário-Seed**: Garante a reprodutibilidade dos experimentos ao associar um `seed` (semente de aleatoriedade) específico a cada cenário de simulação.
-   **Execução Paralela**: Gerencia a execução de múltiplos processos de simulação em paralelo para acelerar a conclusão dos experimentos, utilizando o número de núcleos de processamento disponíveis na máquina.
-   **Gerenciamento de Processos Híbrido**: Lança processos em paralelo até um limite configurável e, à medida que um termina, inicia o próximo, otimizando o uso de recursos.
-   **Barra de Progresso Detalhada**: Fornece feedback visual em tempo real sobre o progresso da execução, incluindo porcentagem de conclusão, tempo decorrido e tempo estimado para o término (ETA).
-   **Logging Robusto**: Registra todas as ações, avisos e erros em um arquivo de log detalhado, facilitando o diagnóstico de problemas.
-   **Coleta e Consolidação de Resultados**: Coleta métricas de cada simulação e as consolida em um único arquivo CSV para fácil análise. Além disso, gera um arquivo de resumo com estatísticas agregadas.
-   **Mecanismo de Espera Inteligente**: Utiliza `inotifywait` (se disponível) ou um mecanismo de *polling* para aguardar de forma eficiente a criação de arquivos necessários entre as etapas da simulação.
-   **Verificação de Dependências**: Checa a existência de dependências Python e do próprio SUMO antes de iniciar a execução.




## 3. Pré-requisitos

Antes de executar o script, certifique-se de que o seguinte ambiente está configurado:

-   **Sistema Operacional**: Um sistema baseado em Linux (devido ao uso de `bash`, `nproc`, `inotifywait`, etc.).
-   **Bash**: Versão 5 ou superior é recomendada, especialmente para a funcionalidade `wait -n`.
-   **SUMO**: O simulador SUMO deve estar instalado e o executável `sumo` deve estar no `PATH` do sistema. A variável de ambiente `SUMO_HOME` também deve ser configurada corretamente.
-   **Python**: Python 3.x.
-   **Dependências Python**: As seguintes bibliotecas Python são necessárias:
    -   `traci` (geralmente vem com a instalação do SUMO)
    -   `shapely`
    -   `numpy`
    -   `pandas`
    -   `networkx`
    -   `sumolib` (geralmente vem com a instalação do SUMO)
    O script verifica a presença dessas bibliotecas e emite um aviso se alguma estiver faltando.
-   **Arquivos de Simulação**: Os arquivos de rede (`.net.xml`), e principalmente os arquivos de rotas (`rotas_*.rou.xml`) devem estar presentes no mesmo diretório onde o script é executado.

## 4. Configuração

O comportamento do script é controlado por uma série de variáveis definidas no seu início. Abaixo estão as principais seções de configuração:

### 4.1. Parâmetros de Simulação

Estas arrays definem o espaço de parâmetros que será explorado:

```bash
ERS=(10 20 30)       # Número de Estações de Recarga
VES=(5 10 20)        # Porcentagem de Veículos Elétricos
TRS=(0.2)            # Tempo de Recarga (em horas)
METHODS=("random" "greedy" "grasp") # Heurísticas de alocação
```

### 4.2. Cenários e Seeds

Esta seção mapeia cada cenário de simulação a um `seed` específico, garantindo que a mesma simulação seja executada com os mesmos parâmetros aleatórios, tornando os resultados comparáveis e reprodutíveis.

```bash
SCENARIOS=(0 1 2 3 4)
SEEDS=(2025 2026 2027 2028 2029)
```

**Importante**: As arrays `SCENARIOS` e `SEEDS` devem ter o mesmo número de elementos.

### 4.3. Configurações de Execução

```bash
THREADS=${THREADS:-$(nproc)} # Define o número de threads (processos) a serem usados pelo SUMO.
CAPACITY=5                   # Capacidade de vagas por estação de recarga.
SERVER_ID="SERVIDOR_2"       # Identificador para os logs.
MAX_PARALLEL_METHODS=2       # Número máximo de execuções do `controlador_pa_opt.py` em paralelo.
```

### 4.4. Tuning do Mecanismo de Espera

```bash
USE_INOTIFY=0   # 1 para usar inotifywait, 0 para usar polling.
POLL_SEC=1      # Intervalo de checagem em segundos (modo polling).
POLL_MAX=900    # Tempo máximo de espera em segundos (15 minutos).
```



## 5. Como Usar

1.  **Prepare o Ambiente**: Certifique-se de que todos os pré-requisitos estão instalados e configurados.
2.  **Organize os Arquivos**: Coloque o script `servidor2_tr02_hibrido.sh`, o `controlador_pa_opt.py`, e todos os arquivos de rotas (`rotas_*.rou.xml`) e de rede (`.net.xml`) no mesmo diretório.
3.  **Configure os Parâmetros**: Edite o script para definir os parâmetros de simulação (`ERS`, `VES`, `TRS`, `METHODS`, `SCENARIOS`, `SEEDS`) conforme desejado.
4.  **Execute o Script**: Abra um terminal no diretório e execute o script:

    ```bash
    bash servidor2_tr02_hibrido.sh
    ```

5.  **Acompanhe o Progresso**: O script exibirá uma barra de progresso no terminal. Você também pode monitorar o arquivo de log em tempo real:

    ```bash
    tail -f logs/servidor2_*.log
    ```

6.  **Analise os Resultados**: Após a conclusão, os resultados estarão disponíveis no arquivo CSV e no arquivo de resumo.

## 6. Estrutura de Saída

O script cria a seguinte estrutura de diretórios e arquivos:

-   `logs/`: Contém os arquivos de log detalhados de cada execução do script principal.
    -   `servidor2_*.log`
-   `output_servidor2/`: Armazena os arquivos de saída gerados pelo `controlador_pa_opt.py`, principalmente os arquivos `.add.xml` que definem os postos de recarga.
-   `results_servidor2/`: Organiza os logs específicos de cada `first_run` e `second_run` em uma estrutura hierárquica, facilitando a depuração de uma simulação específica.
    -   `ER<er>_VE<ve>_TR<tr>/<method>/scenario_<scenario>_seed_<seed>/`
        -   `<method>_first_run.log`
        -   `<method>_second_run.log`
-   `results_servidor2_metrics.csv`: O arquivo CSV consolidado com as métricas de todas as simulações executadas. Cada linha representa uma execução completa (first run + second run).
-   `resumo_servidor2_hibrido_multiseed.txt`: Um arquivo de texto com um resumo estatístico do tempo de execução para cada heurística.


## 7. Detalhes do Fluxo de Execução

O script opera através de uma série de loops aninhados que iteram sobre cada combinação de parâmetros definida.

1.  **Inicialização**:
    -   Define as variáveis e cria os diretórios de saída.
    -   Verifica as dependências.
    -   Inicializa o arquivo CSV com o cabeçalho.
    -   Calcula o número total de execuções e inicializa a barra de progresso.

2.  **Loop Principal**:
    -   O script itera sobre `ERS`, `VES`, `TRS` e `SCENARIOS`.
    -   Para cada combinação, ele entra em um sub-bloco para gerenciar a execução paralela das `METHODS` (heurísticas).

3.  **Gerenciamento Paralelo (por cenário)**:
    -   Para um dado cenário (e seu `seed` correspondente), o script lança as simulações para cada `method` em paralelo, respeitando o limite `MAX_PARALLEL_METHODS`.
    -   A função `run_simulation_for_method` é chamada como um processo em segundo plano (`&`).

4.  **Execução de uma Simulação (`run_simulation_for_method`)**:
    -   **First Run**: Executa o `controlador_pa_opt.py` no modo `first_run`. O tempo de início é registrado.
    -   **Espera**: A função `wait_for_add` é chamada para aguardar a criação do arquivo `.add.xml` pelo `first_run`.
    -   **Cópia e Registro**: Uma vez que o `.add.xml` é encontrado, ele é copiado para um novo nome que inclui o `seed` (para evitar sobrescritas) e o tempo do `first_run` é calculado.
    -   **Second Run**: Executa o `controlador_pa_opt.py` no modo `second_run`, usando o `.add.xml` recém-criado. O tempo desta etapa também é medido.
    -   **Coleta de Métricas**: Após a conclusão do `second_run`, o script extrai métricas do `.add.xml` (número de estações, capacidade total) e escreve uma nova linha no arquivo CSV consolidado com todos os parâmetros e tempos medidos.

5.  **Sincronização e Progresso**:
    -   O loop principal usa `wait -n` para aguardar que qualquer um dos processos em segundo plano termine.
    -   A cada término, a barra de progresso é atualizada (`tick_progress`).
    -   Se houver mais métodos na fila para o cenário atual, um novo processo é lançado.

6.  **Finalização**:
    -   Após todos os loops terminarem, o script calcula o tempo total de execução.
    -   Ele então lê os arquivos de tempo temporários (um para cada método) e usa `awk` para calcular estatísticas (total, média, min, max), que são salvas no arquivo de resumo `resumo_*.txt`.


