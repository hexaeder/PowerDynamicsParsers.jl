# CIM Components Analysis

This document provides a complete analysis of the CIM (Common Information Model) files in the verkleinert-CIM-Export-Test5 dataset.

## File Overview

The dataset contains 7 CIM XML files representing different aspects of a power system model:

- **EQ** (Equipment Core): Physical equipment definitions
- **SSH** (Steady State Hypothesis): Operational parameters and settings
- **TP** (Topology): Network connectivity
- **SV** (State Variables): Power flow results
- **DL** (Diagram Layout): Visual representation
- **GL** (Geographical Location): Geographic positioning
- **DY** (Dynamics): Dynamic model parameters

## 1. Equipment Core File (20151231T2300Z_YYY_EQ_.xml)

**Profile**: `http://entsoe.eu/CIM/EquipmentCore/3/1`, `http://entsoe.eu/CIM/EquipmentShortCircuit/3/1`

**Defines**: The complete electrical equipment of the power system

### Physical Equipment (Count: 12 objects)
- **3 × ACLineSegment**: Transmission lines (EHV Line 65, 219, 298)
- **6 × BusbarSection**: Electrical buses (EHV Bus 41, 42, 69, 70, 325, 326)
- **2 × SynchronousMachine**: Generators (EHV Gen 256, EHV Gen 256-2)
- **1 × ConformLoad**: Load (EHV Load 181)

### Equipment Characteristics
- **2 × ThermalGeneratingUnit**: Generator units with fuel type (gas)
- **2 × FossilFuel**: Fuel specifications
- **1 × BaseVoltage**: 380 kV system voltage level

### Network Organization
- **1 × Substation**: 1-EHVHV-mixed-all-2-sw
- **3 × VoltageLevel**: Equipment groupings by voltage
- **1 × GeographicalRegion**: Regional organization
- **1 × SubGeographicalRegion**: Sub-regional organization

### Connection Points
- **15 × Terminal**: Electrical connection points for equipment

### Operational Limits
- **12 × OperationalLimitSet**: Limit definitions for buses and lines
- **6 × CurrentLimit**: Current ratings (5200 A)
- **12 × VoltageLimit**: Voltage limits (342-418 kV range)
- **3 × OperationalLimitType**: Limit categories (patl, highVoltage, lowVoltage)

### Control Systems
- **2 × RegulatingControl**: Voltage control systems (380 kV target)

### Load Modeling
- **1 × LoadResponseCharacteristic**: Load behavior model
- **1 × ConformLoadGroup**: Load grouping
- **1 × LoadArea**: Load area definition
- **1 × SubLoadArea**: Sub-area definition

**Uses**: Base CIM classes, no external references (foundation file)

---

## 2. Steady State Hypothesis File (20151231T2300Z_XX_YYY_SSH_.xml)

**Profile**: `http://entsoe.eu/CIM/SteadyStateHypothesis/1/1`

**Depends on**: Equipment file (uuid:3c320e48-316e-45f0-81b5-49377d7ff5a1)

**Defines**: Operational state and settings for the equipment

### Generator Operation (2 objects)
- **2 × ThermalGeneratingUnit**: Power factor settings (normalPF = 0)

### Control Settings (2 objects)
- **2 × RegulatingControl**: 
  - Voltage control enabled
  - Target value: 380 kV
  - Discrete mode: false

### Load Operation (1 object)
- **1 × ConformLoad**: Active load values (P=400, Q=200)

### Connection States (15 objects)
- **15 × Terminal**: All terminals connected (ACDCTerminal.connected = true)

**Uses**: References 15 Terminal IDs from Equipment file, 2 ThermalGeneratingUnit IDs, 2 RegulatingControl IDs, 1 ConformLoad ID

---

## 3. Topology File (20151231T2300Z_XX_YYY_TP_.xml)

**Profile**: `http://entsoe.eu/CIM/Topology/4/1`

**Depends on**: Equipment file (uuid:3c320e48-316e-45f0-81b5-49377d7ff5a1)

**Defines**: Electrical connectivity and topological structure

### Topological Structure (3 objects)
- **3 × TopologicalNode**: Electrical connection nodes
  - Node 1: `_29c82eb3-e0d9-5dd7-dc97-0540a6b5a760` (connects 6 terminals)
  - Node 2: `_1401507a-a141-6574-fb92-f36f15d8044d` (connects 3 terminals)  
  - Node 3: `_b6310707-9e85-920d-ada2-b5efeb625dd5` (connects 6 terminals)

### Terminal-Node Mapping (15 objects)
- **15 × Terminal**: Maps each terminal to its topological node

**Uses**: References all 15 Terminal IDs from Equipment file to establish connectivity

---

## 4. State Variables File (20151231T2300Z_XX_YYY_SV_.xml)

**Profile**: `http://entsoe.eu/CIM/StateVariables/4/1`

**Depends on**: Topology file (uuid:54e0e14e-7286-43ee-a8d8-a84587e0e47b) and SSH file (uuid:8f1343b6-a138-4e91-995a-af6fa1fbdb2f)

**Defines**: Power flow results and electrical state

### Power Flow Results (9 objects)
- **9 × SvPowerFlow**: Active and reactive power flows at terminals
  - P values range: -368.73 to 205.285 MW
  - Q values range: -109.495 to 58.8916 MVAr

### Voltage Results (3 objects)  
- **3 × SvVoltage**: Voltage magnitudes and angles at topological nodes

### System State (1 object)
- **1 × TopologicalIsland**: Connected system island

**Uses**: References Terminal IDs from Equipment file and TopologicalNode IDs from Topology file

---

## 5. Diagram Layout File (20151231T2300Z_XX_YYY_DL_.xml)

**Profile**: `http://entsoe.eu/CIM/DiagramLayout/3/1`

**Depends on**: Equipment file and Topology file

**Defines**: Visual representation and positioning

### Diagram Structure (1 object)
- **1 × Diagram**: "1-EHVHV-mixed-all-2-sw(1)" with negative orientation

### Visual Elements (6 objects)
- **6 × DiagramObject**: Visual representations of power system components
  - Equipment graphics with rotation angles (75°, 180°, 348°)
  - Line and bus graphics

### Positioning (11 objects)
- **11 × DiagramObjectPoint**: Coordinate points for visual elements

**Uses**: References Equipment IDs for visual representation

---

## 6. Geographical Location File (20151231T2300Z_XX_YYY_GL_.xml)

**Profile**: Geographic location information

**Defines**: Physical positioning of equipment

### Coordinate System (1 object)
- **1 × CoordinateSystem**: Spatial reference system

### Geographic Positioning (6 objects)
- **3 × Location**: Geographic locations 
- **3 × PositionPoint**: Coordinate points

**Uses**: References to equipment for geographic positioning

---

## 7. Dynamics File (20151231T2300Z_XX_YYY_DY_.xml)

**Profile**: Dynamic modeling parameters

**Defines**: Dynamic behavior models for stability analysis

### Load Dynamics (3 objects)
- **1 × EnergyConsumer**: Dynamic load model
- **1 × LoadAggregate**: Aggregated load model  
- **1 × LoadStatic**: Static load component

### Generator Dynamics (2 objects)
- **2 × SynchronousMachineTimeConstantReactance**: Generator dynamic models with time constants and reactances

**Uses**: References equipment IDs for dynamic model association

---

## Cross-File Dependencies

```
EQ (Equipment) ←── SSH (adds operational data)
EQ (Equipment) ←── TP (adds topology)
EQ (Equipment) ←── DL (adds visuals)  
EQ (Equipment) ←── GL (adds geography)
EQ (Equipment) ←── DY (adds dynamics)
TP (Topology) + SSH (Operations) ←── SV (adds power flow results)
```

## Summary Statistics

| File | Profile | Objects | Key Component Types |
|------|---------|---------|-------------------|
| EQ   | Equipment Core | 76 | ACLineSegment(3), BusbarSection(6), SynchronousMachine(2), Terminal(15) |
| SSH  | Steady State | 22 | ThermalGeneratingUnit(2), RegulatingControl(2), Terminal(15) |
| TP   | Topology | 18 | TopologicalNode(3), Terminal(15) |
| SV   | State Variables | 13 | SvPowerFlow(9), SvVoltage(3), TopologicalIsland(1) |
| DL   | Diagram Layout | 18 | DiagramObject(6), DiagramObjectPoint(11) |
| GL   | Geographic | 7 | Location(3), PositionPoint(3) |
| DY   | Dynamics | 5 | Load models(3), Generator models(2) |

**Total System**: 159 CIM objects representing a 380 kV power system with 2 generators, 1 load, 3 transmission lines, and 6 buses.