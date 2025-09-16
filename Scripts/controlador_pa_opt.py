import traci
import random
import os
import sys
import xml.etree.ElementTree as ET
from shapely.geometry import LineString
import pickle
import networkx as nx
import argparse
import time
import csv
import re
from functools import lru_cache  # <-- (S2) cache

# Garante que o caminho para as ferramentas do SUMO está no PYTHONPATH
if 'SUMO_HOME' in os.environ:
    tools = os.path.join(os.environ['SUMO_HOME'], 'tools')
    sys.path.append(tools)
else:
    sys.exit("Declare a variável de ambiente 'SUMO_HOME'")

# --- ADICIONADO (S1): índices globais e grafo para a função cacheada
_graph = None
_lane_to_edge = {}
_edge_nodes = {}
_lane_len_index = {}

# --- ADICIONADO (S1): Pré-indexa a rede UMA vez
def build_net_indexes(net_file):
    """
    Monta:
      - lane_to_edge: lane_id -> edge_id
      - edge_nodes: edge_id -> (from_node, to_node)
      - lane_len: lane_id -> length
    """
    net_tree = ET.parse(net_file)
    net_root = net_tree.getroot()

    lane_to_edge = {}
    edge_nodes = {}
    lane_len = {}

    for edge in net_root.findall(".//edge"):
        eid = edge.attrib.get("id")
        f = edge.attrib.get("from")
        t = edge.attrib.get("to")
        if f and t:
            edge_nodes[eid] = (f, t)
        for lane in edge.findall("lane"):
            lid = lane.attrib.get("id")
            lane_to_edge[lid] = eid
            lane_len[lid] = float(lane.attrib.get("length", "0"))

    return lane_to_edge, edge_nodes, lane_len

# --- ADICIONADO (S2): Proximidade cacheada sem reparse de XML
@lru_cache(maxsize=None)
def compute_lane_proximity_cached(lane1, lane2, distance_threshold=None):
    """
    Distância na rede entre lane1 e lane2 usando índices pré-computados + _graph.
    Evita reparse do XML e usa cache para chamadas repetidas.
    """
    # lane -> edge
    e1 = _lane_to_edge.get(lane1)
    e2 = _lane_to_edge.get(lane2)
    if not e1 or not e2:
        return float('inf')

    # edge -> (from, to)
    f1, t1 = _edge_nodes.get(e1, (None, None))
    f2, t2 = _edge_nodes.get(e2, (None, None))
    if t1 is None or f2 is None:
        return float('inf')

    if (_graph is None) or (t1 not in _graph) or (f2 not in _graph):
        return float('inf')

    try:
        dist = nx.shortest_path_length(_graph, source=t1, target=f2, weight="weight")
        if distance_threshold is not None and dist >= distance_threshold:
            return dist
        return dist
    except (nx.NodeNotFound, nx.NetworkXNoPath):
        return float('inf')

# --- ADICIONADO: Função para ler o log e extrair teleports
def parse_teleports(log_path):
    try:
        with open(log_path, 'r') as f:
            for line in f:
                match = re.search(r"Teleports:\s+(\d+)", line)
                if match:
                    return int(match.group(1))
    except FileNotFoundError:
        print(f"Aviso: Arquivo de log não encontrado em {log_path}")
        return 0
    return 0

# --- ADICIONADO: Função para calcular a distância na rede
def compute_distance_to_station(graph, net_file, start_edge_id, end_edge_id):
    try:
        # Encontra os nós de destino da aresta inicial e de origem da aresta final
        _, from_node_start = find_edge_nodes(net_file, start_edge_id)
        to_node_end, _ = find_edge_nodes(net_file, end_edge_id)
        if from_node_start and to_node_end and graph.has_node(from_node_start) and graph.has_node(to_node_end):
            dist = nx.shortest_path_length(graph, source=from_node_start, target=to_node_end, weight="weight")
            return dist
    except (nx.NetworkXNoPath, nx.NodeNotFound):
        return float('inf') # Retorna infinito se não houver caminho
    return float('inf')

# Funções para os métodos de seleção
def select_random_stations(lane_visits, num_stations):
    print("----- Método: Random -----")
    visited_lanes = list(lane_visits.keys())
    print("Lanes visitadas (elétricos):", visited_lanes)
    selected_stations = random.sample(visited_lanes, num_stations)
    print("Lanes selecionadas (random):", selected_stations)
    return selected_stations

def select_greedy_stations(lane_visits, num_stations):
    print("----- Método: Greedy -----")
    sorted_lanes = sorted(lane_visits.items(), key=lambda item: item[1], reverse=True)
    selected_stations = [lane_id for lane_id, count in sorted_lanes[:num_stations]]
    print("Lanes selecionadas (greedy):", selected_stations)
    return selected_stations

def get_lane_shape(net_file, lane_id):
    tree = ET.parse(net_file)
    root = tree.getroot()
    for lane in root.findall(".//lane"):
        if lane.attrib["id"] == lane_id:
            shape_str = lane.attrib["shape"]
            points = [tuple(map(float, point.split(","))) for point in shape_str.split()]
            return points
    return None

def segment_distance(seg1, seg2):
    line1 = LineString(seg1)
    line2 = LineString(seg2)
    return line1.distance(line2)

def distance_between_lanes(net_file, lane1_id, lane2_id):
    shape1 = get_lane_shape(net_file, lane1_id)
    shape2 = get_lane_shape(net_file, lane2_id)
    if not shape1 or not shape2:
        return float('inf')
    min_distance = float('inf')
    for i in range(len(shape1) - 1):
        for j in range(len(shape2) - 1):
            seg1 = (shape1[i], shape1[i+1])
            seg2 = (shape2[j], shape2[j+1])
            distance = segment_distance(seg1, seg2)
            min_distance = min(min_distance, distance)
    return min_distance

def create_graph_from_net(net_file, lane_visits=None):
    net_tree = ET.parse(net_file)
    net_root = net_tree.getroot()
    graph = nx.DiGraph()
    added_edges = set()
    for edge in net_root.findall(".//edge"):
        edge_id = edge.attrib.get("id")
        from_node = edge.attrib.get("from")
        to_node = edge.attrib.get("to")
        if from_node and to_node:
            length = float(edge.attrib.get("length", "1000"))
            weight = length
            graph.add_edge(from_node, to_node, id=edge_id, weight=weight)
            added_edges.add(edge_id)
            if not edge.attrib.get("function") == "internal":
                graph.add_edge(to_node, from_node, id=f"-{edge_id}", weight=weight)
    with open("edges_no_grafo.txt", "w") as f:
        f.write(f"Total de edges adicionadas ao grafo: {len(added_edges)}\n")
        for edge in sorted(added_edges):
            f.write(f"{edge}\n")
    return graph

def get_edge_from_lane(net_file, lane_id):
    tree = ET.parse(net_file)
    root = tree.getroot()
    for edge in root.findall(".//edge"):
        for lane in edge.findall(".//lane"):
            if lane.attrib["id"] == lane_id:
                return edge.attrib["id"]
    return None

def distance_between_edges_nx(graph, net_file, edge1_id, edge2_id):
    try:
        from1, to1 = find_edge_nodes(net_file, edge1_id)
        from2, to2 = find_edge_nodes(net_file, edge2_id)
        if from1 is None or to2 is None:
            print(f"Aviso: Não foi possível encontrar nós para as arestas {edge1_id} ou {edge2_id}")
            return float('inf')
        path_length = nx.shortest_path_length(graph, source=to1, target=from2, weight="weight")
        return path_length
    except nx.NetworkXNoPath:
        print(f"Aviso: Não há caminho entre {edge1_id} e {edge2_id}")
        return float('inf')
    except nx.NodeNotFound as e:
        print(f"Aviso: Nó não encontrado no grafo - {e}")
        return float('inf')

def find_edge_nodes(net_file, edge_id):
    tree = ET.parse(net_file)
    root = tree.getroot()
    for edge in root.findall(".//edge"):
        if edge.attrib["id"] == edge_id:
            return edge.attrib.get("from"), edge.attrib.get("to")
    return None, None

def select_best_lane_in_edge(net_file, edge_id, lane_visits):
    tree = ET.parse(net_file)
    root = tree.getroot()
    best_lane = None
    best_score = -1
    for edge in root.findall(".//edge"):
        if edge.attrib["id"] == edge_id:
            lanes = edge.findall("lane")
            for lane in lanes:
                lane_id = lane.attrib["id"]
                score = lane_visits.get(lane_id, 0)
                if score > best_score:
                    best_score = score
                    best_lane = lane_id
    return best_lane

def select_grasp_stations(lane_visits, num_stations, graph, net_file):
    print("----- Método: GRASP (Ultra Otimizado) -----")
    best_solution = []
    best_score = -1
    visited_lanes = list(lane_visits.keys())
    print("Lanes visitadas (elétricos):", visited_lanes)
    lrc = sorted(visited_lanes, key=lambda lane: lane_visits.get(lane, 0), reverse=True)[:num_stations * 5]
    print("LRC (GRASP):", lrc)

    for _ in range(10):  # Número de iterações ajustável
        current_solution = []
        tabu_set = set()

        if not lrc:
            print("LRC vazia, saindo do loop.")
            break

        most_visited_lane = lrc[0]
        current_solution.append(most_visited_lane)
        tabu_set.add(most_visited_lane)

        # (S2) Usa versão cacheada
        for lane in lrc:
            if lane != most_visited_lane and compute_lane_proximity_cached(most_visited_lane, lane) < 500:
                tabu_set.add(lane)

        while len(current_solution) < num_stations:
            valid_lanes = [lane for lane in lrc if lane not in tabu_set]
            if not valid_lanes:
                print("Não há mais lanes válidas para adicionar à solução.")
                break

            selected_lane = random.choice(valid_lanes)
            current_solution.append(selected_lane)
            tabu_set.add(selected_lane)

            # (S2) Usa versão cacheada
            for lane in lrc:
                if lane != selected_lane and compute_lane_proximity_cached(selected_lane, lane) < 500:
                    tabu_set.add(lane)

        current_score = sum(lane_visits[lane] for lane in current_solution if lane in lane_visits)

        if current_score > best_score:
            best_score = current_score
            best_solution = current_solution

    print("Lanes selecionadas (GRASP Ultra Otimizado):", best_solution)
    return best_solution

def get_edge_from_lane(net_file, lane_id):
    tree = ET.parse(net_file)
    root = tree.getroot()
    for edge in root.findall(".//edge"):
        for lane in edge.findall(".//lane"):
            if lane.attrib["id"] == lane_id:
                return edge.attrib["id"]
    return None

def compute_lane_proximity(graph, net_file, lane1, lane2):
    edge1 = get_edge_from_lane(net_file, lane1)
    edge2 = get_edge_from_lane(net_file, lane2)
    if edge1 is None or edge2 is None:
        with open("edges_nao_encontradas.txt", "a") as f:
            f.write(f"Erro: Lane {lane1} → Edge {edge1} ou Lane {lane2} → Edge {edge2} não existe!\n")
        return float('inf')
    from1, to1 = find_edge_nodes(net_file, edge1)
    from2, to2 = find_edge_nodes(net_file, edge2)
    if from1 is None or to1 is None or from2 is None or to2 is None:
        with open("edges_nao_encontradas.txt", "a") as f:
            f.write(f"⚠️ Erro: Nós da Edge {edge1} ({from1}, {to1}) ou Edge {edge2} ({from2}, {to2}) não encontrados!\n")
        return float('inf')
    if to1 not in graph or from2 not in graph:
        with open("edges_nao_encontradas.txt", "a") as f:
            f.write(f"🚨 Erro: Nó {to1} ou {from2} NÃO está no grafo!\n")
        return float('inf')
    try:
        return nx.shortest_path_length(graph, source=to1, target=from2, weight="weight")
    except nx.NetworkXNoPath:
        return float('inf')

def generate_parking_areas_file(selected_lanes, output_dir, base_filename, capacity, net_file="cologne2.net.xml"):
    os.makedirs(output_dir, exist_ok=True)
    add_file = os.path.abspath(os.path.join(output_dir, f"parking_areas_{base_filename}.add.xml"))

    net_tree = ET.parse(net_file)
    net_root = net_tree.getroot()

    lane_len = {}
    for lane in net_root.findall(".//lane"):
        lid = lane.attrib.get("id")
        length = float(lane.attrib.get("length", "0"))
        lane_len[lid] = length

    root = ET.Element("additional")
    skipped = []

    MIN_SPAN = 8.0
    DESIRED_SPAN = 15.0
    MARGIN = 1.0

    for lane_id in selected_lanes:
        L = lane_len.get(lane_id, 0.0)
        if L <= MIN_SPAN or lane_id.startswith(":"):
            skipped.append((lane_id, L))
            continue
        span = min(DESIRED_SPAN, max(MIN_SPAN, L - 2*MARGIN))
        startPos = max(MARGIN, min(5.0, L - span - MARGIN))
        endPos = min(L - MARGIN, startPos + span)
        if endPos - startPos < 1.0 or endPos <= startPos or endPos > L or startPos < 0:
            skipped.append((lane_id, L))
            continue

        parking_area = ET.SubElement(root, "parkingArea", {
            "id": f"parking_area_{lane_id}",
            "lane": lane_id,
            "startPos": f"{startPos:.2f}",
            "endPos": f"{endPos:.2f}",
            "roadsideCapacity": str(capacity)
        })
        ET.SubElement(parking_area, "param", {"key": "capacity", "value": str(capacity)})

    tree = ET.ElementTree(root)
    tree.write(add_file, xml_declaration=True, encoding="UTF-8")

    if skipped:
        with open(os.path.join(output_dir, "parking_areas_skipped.txt"), "w") as f:
            for lid, L in skipped:
                f.write(f"{lid}\tlength={L}\n")

    print(f"📄 .add.xml gerado: {add_file}")
    if skipped:
        print(f"⚠️  Lanes sem PA (curtas ou inválidas): {len(skipped)}. Veja parking_areas_skipped.txt")
    return add_file

# Define a porcentagem de veículos com bateria baixa
LOW_BATTERY_PERCENTAGE = 100

def set_low_battery_percentage(route_file, percentage):
    tree = ET.parse(route_file)
    root = tree.getroot()
    vehicles = [v.get('id') for v in root.findall(".//vehicle") if v.get('type') == 'electric_vehicle']
    num_low_battery = int(len(vehicles) * percentage / 100)
    low_battery_vehicles = set(vehicles[:num_low_battery])
    print(f"Veículos com bateria baixa definidos: {low_battery_vehicles}")
    return low_battery_vehicles

def run_simulation(args, graph, add_file=None):
    import traci, os
    trip_info_file = "output/tripinfo.xml"
    base_name = os.path.basename(args.route_file).replace('_mod.rou.xml', '')
    log_file = f"output/{args.method}_{args.mode}_{base_name}.log"

    sumoCmd = [
        "sumo", "-c", "cologne.sumocfg",
        "--route-files", args.route_file,
        "--tripinfo-output", trip_info_file,
        "--duration-log.statistics", "--log", log_file, "--verbose",
        "--step-length", str(args.step_length),
        "--threads", str(args.threads),
        "--seed", str(args.seed)
    ]
    if add_file:
        sumoCmd += ["--additional-files", f"cologne.poly.xml,{add_file}"]
    else:
        sumoCmd += ["--additional-files", "cologne.poly.xml"]

    t0 = time.time()
    traci.start(sumoCmd)

    lane_visits = {}
    low_battery_vehicles = set_low_battery_percentage(args.route_file, LOW_BATTERY_PERCENTAGE)
    visited_parking = {}

    while traci.simulation.getMinExpectedNumber() > 0:
        traci.simulationStep()

        if args.mode == "second_run":
            for vehicle_id in traci.vehicle.getIDList():
                if vehicle_id in low_battery_vehicles:
                    try:
                        current_battery = float(traci.vehicle.getParameter(vehicle_id, "device.battery.actualBatteryCapacity"))
                        if current_battery > 12000:
                            traci.vehicle.setParameter(vehicle_id, "device.battery.actualBatteryCapacity", "12000")
                            print(f"🔋 Veículo {vehicle_id} definido com bateria baixa (12000 Wh).")
                    except traci.exceptions.TraCIException:
                        continue

        for vid in list(visited_parking.keys()):
            data = visited_parking[vid]
            if vid not in traci.vehicle.getIDList():
                continue
            if data["state"] == "waiting":
                try:
                    current_lane = traci.vehicle.getLaneID(vid)
                    if current_lane == data["parking_lane"] and "t_arrive_lane" not in data:
                        data["t_arrive_lane"] = traci.simulation.getTime()
                        data["t_queue"] = data["t_arrive_lane"] - data["t_dec"]
                        print(f"✅ Veículo {vid} chegou à PA. T_fila: {data['t_queue']:.2f}s.")
                        orig_target = data.get("original_target")
                        if orig_target:
                            traci.vehicle.changeTarget(vid, orig_target)
                        visited_parking[vid]["state"] = "recharged"
                        if vid in low_battery_vehicles:
                            low_battery_vehicles.remove(vid)
                        print(f"🔋 Veículo {vid} recarregado e marcado como 'recharged'.")
                except traci.exceptions.TraCIException:
                    continue

        active_low_battery_vehicles = {v for v in low_battery_vehicles if v not in visited_parking}

        for vehicle_id in active_low_battery_vehicles:
            if vehicle_id not in traci.vehicle.getIDList():
                continue
            try:
                battery_level = float(traci.vehicle.getParameter(vehicle_id, "device.battery.actualBatteryCapacity"))
                vehicle_position = traci.vehicle.getPosition(vehicle_id)
            except traci.exceptions.TraCIException:
                continue

            if battery_level < 15000 and args.mode == "second_run":
                print(f"⚡ Veículo {vehicle_id} com bateria baixa ({battery_level:.0f} Wh), procurando Parking Area...")
                available_parkings = []
                current_edge = traci.vehicle.getRoadID(vehicle_id)

                for parking_id in traci.parkingarea.getIDList():
                    try:
                        parking_lane_id = traci.parkingarea.getLaneID(parking_id)
                        if parking_lane_id not in traci.lane.getIDList():
                            continue
                        station_edge = parking_lane_id.split('_')[0]
                        network_distance = compute_distance_to_station(graph, args.net_file, current_edge, station_edge)
                        if network_distance != float('inf'):
                            available_parkings.append((parking_id, parking_lane_id, network_distance))
                    except traci.exceptions.TraCIException:
                        continue

                available_parkings.sort(key=lambda x: (x[2], traci.parkingarea.getVehicleCount(x[0])))

                if available_parkings:
                    chosen_parking, parking_lane_id, min_distance = available_parkings[0]
                    print(f"🚗 Veículo {vehicle_id} indo para Parking Area {chosen_parking}, a {int(min_distance)}m de distância.")
                    current_edge = traci.vehicle.getRoadID(vehicle_id)
                    station_edge = parking_lane_id.split('_')[0]
                    dist_to_station = compute_distance_to_station(graph, args.net_file, current_edge, station_edge)
                    original_target = traci.vehicle.getRoute(vehicle_id)[-1]
                    visited_parking[vehicle_id] = {
                        "state": "waiting",
                        "parking_id": chosen_parking,
                        "parking_lane": parking_lane_id,
                        "original_target": original_target,
                        "t_dec": traci.simulation.getTime(),
                        "d_to_station": dist_to_station
                    }
                    try:
                        traci.vehicle.changeTarget(vehicle_id, station_edge)
                        charge_duration_s = int(args.tr_min * 60)
                        traci.vehicle.setParkingAreaStop(vehicle_id, chosen_parking, duration=charge_duration_s)
                        print(f"Veículo {vehicle_id} comandado a parar na PA {chosen_parking}.")
                    except traci.exceptions.TraCIException as e:
                        print(f"Erro ao configurar PA para veículo {vehicle_id}: {e}")
                        continue

            if vehicle_id in traci.vehicle.getIDList():
                try:
                    lane_id = traci.vehicle.getLaneID(vehicle_id)
                    if lane_id and not lane_id.startswith(":"):
                        lane_visits[lane_id] = lane_visits.get(lane_id, 0) + 1
                except traci.exceptions.TraCIException:
                    continue

    T_exec = time.time() - t0
    traci.close()

    N_teleport = parse_teleports(log_file)
    t_esperas = [d["t_queue"] for d in visited_parking.values() if "t_queue" in d]
    d_estacoes = [d["d_to_station"] for d in visited_parking.values() if "d_to_station" in d and d["d_to_station"] != float('inf')]

    T_espera_mean = (sum(t_esperas) / len(t_esperas)) if t_esperas else 0.0
    D_estacao_mean = (sum(d_estacoes) / len(d_estacoes) / 1000.0) if d_estacoes else 0.0

    results = {
        "T_exec": T_exec, "N_teleport": N_teleport,
        "T_espera": T_espera_mean, "D_estacao": D_estacao_mean
    }
    return (lane_visits, results) if args.mode == 'first_run' else results

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Controlador de simulação SUMO para alocação de PAs.")
    ap.add_argument("--route_file", required=True)
    ap.add_argument("--method", choices=["random", "greedy", "grasp"], required=True)
    ap.add_argument("--mode", choices=["first_run", "second_run"], required=True)
    ap.add_argument("--add_file", help="Arquivo .add.xml para o second_run.")
    ap.add_argument("--net_file", default="cologne2.net.xml")
    ap.add_argument("--er", type=int, default=10, help="Nº de estações (ER)")
    ap.add_argument("--tr_min", type=float, default=10, help="Tempo de recarga em minutos (TR)")
    ap.add_argument("--capacity", type=int, default=5, help="Vagas por estação")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--rep", type=int, default=1)
    ap.add_argument("--threads", type=int, default=24) #Qtde. de processos por ciclo
    ap.add_argument("--step_length", type=float, default=1.5)
    ap.add_argument("--out_dir", default="output")
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    random.seed(args.seed)

    # Grafo para GRASP e métricas de D_estacao
    graph = create_graph_from_net(args.net_file)

    # (S1) Pré-indexa a rede UMA vez e exporta para globais usadas no cache
    _lane_to_edge, _edge_nodes, _lane_len_index = build_net_indexes(args.net_file)
    _graph = graph  # torna o grafo acessível à função cacheada

    if args.mode == "first_run":
        print(f"🚀 FIRST RUN: Rota={args.route_file}, Método={args.method}")
        lane_visits, _ = run_simulation(args, graph)

        visits_file = f"output/lane_visits_{os.path.basename(args.route_file).replace('_mod.rou.xml', '.pkl')}"
        with open(visits_file, "wb") as f:
            pickle.dump(lane_visits, f)
        print(f"💾 Dados de visitas salvos em {visits_file}")

        base_name = os.path.basename(args.route_file).replace('_mod.rou.xml', '')
        num_stations = args.er
        if args.method == "random":
            selected_lanes = select_random_stations(lane_visits, num_stations)
        elif args.method == "greedy":
            selected_lanes = select_greedy_stations(lane_visits, num_stations)
        elif args.method == "grasp":
            selected_lanes = select_grasp_stations(lane_visits, num_stations, graph, args.net_file)

        base_filename = f"{args.method}_{base_name}_er{args.er}"
        add_file = generate_parking_areas_file(selected_lanes, args.out_dir, base_filename, args.capacity, net_file=args.net_file)
        print(f"📄 Arquivo .add.xml gerado: {add_file}")

    elif args.mode == "second_run":
        if not args.add_file:
            print("❌ Erro: .add.xml é obrigatório para a SECOND RUN.")
            sys.exit(1)

        print(f"🚀 SECOND RUN: Rota={args.route_file}, Método={args.method}")
        results = run_simulation(args, graph, add_file=args.add_file)
        print(f"✅ SECOND RUN concluída!")

        ve_percent_str = re.search(r"rotas_(\d+)", args.route_file)
        ve_percent = int(ve_percent_str.group(1)) if ve_percent_str else 0

        output_csv_file = os.path.join(args.out_dir, "resultados_execucoes.csv")
        row = {
            "heuristic": args.method, "ER": args.er, "VE": ve_percent, "TR": args.tr_min,
            "rep": args.rep, "T_espera": round(results["T_espera"], 2),
            "D_estacao": round(results["D_estacao"], 3), "N_teleport": results["N_teleport"],
            "T_exec": round(results["T_exec"], 3),
            "route_file": os.path.basename(args.route_file), "add_file": os.path.basename(args.add_file)
        }
        file_exists = os.path.isfile(output_csv_file)
        with open(output_csv_file, "a", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=row.keys())
            if not file_exists:
                writer.writeheader()
            writer.writerow(row)
        print(f"📈 Resultados salvos em {output_csv_file}")
