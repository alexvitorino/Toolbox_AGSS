import os
import subprocess
import argparse

def gerar_rotas_sem_vtype(output_file, num_trips):
    """
    Gera um arquivo de rotas com um número total de viagens, sem especificar vTypes.
    """
    comando = [
        "python",
        "/home/alex/sumo/sumo-1.18.0/tools/randomTrips.py",
        "-n", "cologne2.net.xml",
        "-r", output_file,
        "-e", str(num_trips),
        "-p", "1.0",  # Ajustado para gerar mais rápido
        "--vehicle-class", "passenger",
        "--prefix", ""
    ]
    subprocess.run(comando, check=True)
    print(f"Arquivo de rotas '{output_file}' gerado (sem vTypes).")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Gera um arquivo de rotas para a simulação SUMO sem especificar vTypes.")
    parser.add_argument("-t", "--total-trips", type=int, default=10000, help="Número total de viagens a serem geradas.")
    args = parser.parse_args()

    arquivo_saida = "rotas.rou.xml"
    gerar_rotas_sem_vtype(arquivo_saida, args.total_trips)