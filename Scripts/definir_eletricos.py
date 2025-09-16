import xml.etree.ElementTree as ET
import random

def definir_eletricos(input_file, output_file, electric_percentage):
    """
    Modifica um arquivo de rotas para definir uma porcentagem de viagens como elétricas,
    selecionando-as aleatoriamente.
    """
    tree = ET.parse(input_file)
    root = tree.getroot()

    # Adiciona as definições de vType, se não existirem
    if not root.find('vType[@id="veiculo_normal"]'):
        vtype_normal = ET.Element("vType", attrib={
            "id": "veiculo_normal",
            "length": "5",
            "accel": "2.6",
            "decel": "5.0",
            "tau": "1.5",
            "sigma": "0.5",
            "maxSpeed": "60",
            "color": "1,1,0"
        })
        root.insert(0, vtype_normal)

    if not root.find('vType[@id="electric_vehicle"]'):
        vtype_eletrico = ET.Element("vType", attrib={
            "id": "electric_vehicle",
            "length": "4.5", 
            "minGap": "2.50",
            "maxSpeed": "60", 
            "color": "white",
            "accel": "2.6", 
            "decel": "5.0",
            "tau": "1.5" ,
            "sigma": "0.5", 
            "emissionClass": "Energy/unknown"
        })
        # Parâmetros do soulEV65
        vtype_eletrico.append(ET.Element("param", attrib={"key": "has.battery.device", "value": "true"}))
        vtype_eletrico.append(ET.Element("param", attrib={"key": "device.battery.capacity", "value": "64000"})) 
        vtype_eletrico.append(ET.Element("param", attrib={"key": "airDragCoefficient", "value": "0.35"}))
        vtype_eletrico.append(ET.Element("param", attrib={"key": "constantPowerIntake", "value": "100"}))
        vtype_eletrico.append(ET.Element("param", attrib={"key": "frontSurfaceArea", "value": "2.6"}))
        vtype_eletrico.append(ET.Element("param", attrib={"key": "internalMomentOfInertia", "value": "40"})) # Substituído por rotatingMass
        vtype_eletrico.append(ET.Element("param", attrib={"key": "maximumPower", "value": "150000"}))
        vtype_eletrico.append(ET.Element("param", attrib={"key": "propulsionEfficiency", "value": ".98"}))
        vtype_eletrico.append(ET.Element("param", attrib={"key": "radialDragCoefficient", "value": "0.1"}))
        vtype_eletrico.append(ET.Element("param", attrib={"key": "recuperationEfficiency", "value": ".96"})) # Valor alto, ajuste se necessário
        vtype_eletrico.append(ET.Element("param", attrib={"key": "rollDragCoefficient", "value": "0.01"}))
        vtype_eletrico.append(ET.Element("param", attrib={"key": "stoppingThreshold", "value": "0.1"}))
        vtype_eletrico.append(ET.Element("param", attrib={"key": "mass", "value": "1830"}))
        vtype_eletrico.append(ET.Element("param", attrib={"key": "mass", "value": "1830"}))
        root.insert(1, vtype_eletrico)

    # Coleta todos os veículos
    all_vehicles = root.findall('vehicle')

    # Calcula o número de veículos elétricos
    num_vehicles = len(all_vehicles)
    num_electric = int(num_vehicles * electric_percentage)

    # Seleciona aleatoriamente os veículos para serem elétricos
    electric_vehicles = random.sample(all_vehicles, num_electric)

    # Define o 'type' dos veículos selecionados como 'electric_vehicle'
    for vehicle in electric_vehicles:
        vehicle.set("type", "electric_vehicle")

    # Define os veículos restantes como 'veiculo_normal'
    for vehicle in all_vehicles:
        if vehicle not in electric_vehicles:
            vehicle.set("type", "veiculo_normal")

    tree.write(output_file)

if __name__ == "__main__":
    porcentagens = [0.05, 0.10, 0.20]
    for i in range(10): #Gera 10 arquivos para cada porcentagem
        for porcentagem in porcentagens:
            input_file = "rotas.rou.xml"
            output_file = f"rotas_{porcentagem * 100:.0f}_{i}_mod.rou.xml"
            definir_eletricos(input_file, output_file, porcentagem)
            print(f"Arquivo '{output_file}' gerado com {porcentagem * 100:.0f}% de carros elétricos.")