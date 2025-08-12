# CIM Properties Reference Guide

This document provides a comprehensive reference of all properties for each CIM model type found in the dataset, organized by file and showing the complete property structure for Julia implementation.

---

## Equipment Core File (EQ) - Model Types and Properties

### ACLineSegment (Transmission Lines)
**File**: Equipment Core (EQ)  
**Count**: 3 objects  
**Purpose**: AC transmission line electrical parameters

**Literal Properties:**
- `r` - Positive sequence resistance (Ohm) - Float64
- `x` - Positive sequence reactance (Ohm) - Float64  
- `r0` - Zero sequence resistance (Ohm) - Float64
- `x0` - Zero sequence reactance (Ohm) - Float64
- `bch` - Positive sequence shunt susceptance (Siemens) - Float64
- `b0ch` - Zero sequence shunt susceptance (Siemens) - Float64
- `gch` - Positive sequence shunt conductance (Siemens) - Float64
- `g0ch` - Zero sequence shunt conductance (Siemens) - Float64
- `shortCircuitEndTemperature` - Short circuit end temperature (°C) - Float64
- `length` - Line length (km) - Float64

**Reference Properties:**
- `ConductingEquipment.BaseVoltage` → BaseVoltage
- `Equipment.EquipmentContainer` → VoltageLevel (inherited)

**Inherited Properties:**
- `IdentifiedObject.name` - Equipment name - String
- `IdentifiedObject.description` - Description - String (optional)

### SynchronousMachine (Generators)
**File**: Equipment Core (EQ)  
**Count**: 2 objects  
**Purpose**: Synchronous generator electrical parameters

**Literal Properties:**
- `r` - Stator resistance (per unit) - Float64
- `r0` - Zero sequence resistance (per unit) - Float64
- `r2` - Negative sequence resistance (per unit) - Float64
- `x0` - Zero sequence reactance (per unit) - Float64
- `x2` - Negative sequence reactance (per unit) - Float64
- `maxQ` - Maximum reactive power (MVAr) - Float64
- `minQ` - Minimum reactive power (MVAr) - Float64
- `qPercent` - Percentage of generator's maximum reactive power - Float64
- `earthing` - Generator earthing status - Bool
- `earthingStarPointR` - Star point resistance (Ohm) - Float64
- `earthingStarPointX` - Star point reactance (Ohm) - Float64
- `satDirectSubtransX` - Direct axis subtransient reactance (per unit) - Float64
- `satDirectSyncX` - Direct axis synchronous reactance (per unit) - Float64
- `ratedPowerFactor` - Rated power factor - Float64
- `ratedS` - Rated apparent power (MVA) - Float64
- `ratedU` - Rated voltage (kV) - Float64

**Reference Properties:**
- `Equipment.EquipmentContainer` → VoltageLevel
- `RegulatingCondEq.RegulatingControl` → RegulatingControl
- `RotatingMachine.GeneratingUnit` → ThermalGeneratingUnit
- `shortCircuitRotorType` → ShortCircuitRotorKind (enumeration)
- `type` → SynchronousMachineKind (enumeration)

**Inherited Properties:**
- `IdentifiedObject.name` - Generator name - String
- `IdentifiedObject.description` - Description - String

### BusbarSection (Electrical Buses)
**File**: Equipment Core (EQ)  
**Count**: 6 objects  
**Purpose**: Electrical busbars/nodes

**Reference Properties:**
- `Equipment.EquipmentContainer` → VoltageLevel

**Inherited Properties:**
- `IdentifiedObject.name` - Bus name - String

### ConformLoad (Loads)
**File**: Equipment Core (EQ)  
**Count**: 1 object  
**Purpose**: Electrical load definition

**Reference Properties:**
- `Equipment.EquipmentContainer` → VoltageLevel
- `ConformLoad.LoadGroup` → ConformLoadGroup
- `EnergyConsumer.LoadResponse` → LoadResponseCharacteristic

**Inherited Properties:**
- `IdentifiedObject.name` - Load name - String

### ThermalGeneratingUnit (Generator Units)
**File**: Equipment Core (EQ)  
**Count**: 2 objects  
**Purpose**: Generating unit characteristics

**Literal Properties:**
- `initialP` - Initial active power output (MW) - Float64
- `maxOperatingP` - Maximum operating active power (MW) - Float64
- `minOperatingP` - Minimum operating active power (MW) - Float64

**Reference Properties:**
- `Equipment.EquipmentContainer` → Substation

**Inherited Properties:**
- `IdentifiedObject.name` - Unit name - String

### Terminal (Connection Points)
**File**: Equipment Core (EQ)  
**Count**: 15 objects  
**Purpose**: Electrical connection points for equipment

**Literal Properties:**
- `sequenceNumber` - Terminal sequence number - Int64

**Reference Properties:**
- `Terminal.ConductingEquipment` → Equipment (BusbarSection, ACLineSegment, SynchronousMachine, ConformLoad)
- `phases` → PhaseCode (enumeration - typically ABC)

**Inherited Properties:**
- `IdentifiedObject.name` - Terminal name - String

### VoltageLimit (Voltage Limits)
**File**: Equipment Core (EQ)  
**Count**: 12 objects  
**Purpose**: Voltage operating limits

**Literal Properties:**
- `value` - Voltage limit value (kV) - Float64

**Reference Properties:**
- `OperationalLimit.OperationalLimitSet` → OperationalLimitSet
- `OperationalLimit.OperationalLimitType` → OperationalLimitType

**Inherited Properties:**
- `IdentifiedObject.name` - Limit name - String

### CurrentLimit (Current Limits)
**File**: Equipment Core (EQ)  
**Count**: 6 objects  
**Purpose**: Current operating limits

**Literal Properties:**
- `value` - Current limit value (A) - Float64

**Reference Properties:**
- `OperationalLimit.OperationalLimitSet` → OperationalLimitSet
- `OperationalLimit.OperationalLimitType` → OperationalLimitType

**Inherited Properties:**
- `IdentifiedObject.name` - Limit name - String

### OperationalLimitSet (Limit Collections)
**File**: Equipment Core (EQ)  
**Count**: 12 objects  
**Purpose**: Groups of operational limits

**Reference Properties:**
- `OperationalLimitSet.Terminal` → Terminal

**Inherited Properties:**
- `IdentifiedObject.name` - Limit set name - String

### OperationalLimitType (Limit Definitions)
**File**: Equipment Core (EQ)  
**Count**: 3 objects  
**Purpose**: Types of operational limits

**Reference Properties:**
- `direction` → OperationalLimitDirectionKind (enumeration)
- `limitType` → LimitTypeKind (ENTSO-E extension)

**Inherited Properties:**
- `IdentifiedObject.name` - Limit type name - String

### RegulatingControl (Control Systems)
**File**: Equipment Core (EQ)  
**Count**: 2 objects  
**Purpose**: Voltage/power control system definitions

**Reference Properties:**
- `RegulatingControl.Terminal` → Terminal
- `mode` → RegulatingControlModeKind (enumeration - voltage/reactive power)

**Inherited Properties:**
- `IdentifiedObject.name` - Control name - String

### BaseVoltage (Voltage Levels)
**File**: Equipment Core (EQ)  
**Count**: 1 object  
**Purpose**: System voltage level definition

**Literal Properties:**
- `nominalVoltage` - Nominal voltage (kV) - Float64

**Reference Properties:**
- `shortName` - Short name (ENTSO-E extension) - String

**Inherited Properties:**
- `IdentifiedObject.name` - Voltage level name - String
- `IdentifiedObject.description` - Description - String

### VoltageLevel (Equipment Groupings)
**File**: Equipment Core (EQ)  
**Count**: 3 objects  
**Purpose**: Groups equipment by voltage level

**Reference Properties:**
- `VoltageLevel.BaseVoltage` → BaseVoltage
- `VoltageLevel.Substation` → Substation

**Inherited Properties:**
- `IdentifiedObject.name` - Voltage level name - String

### Substation (Physical Locations)
**File**: Equipment Core (EQ)  
**Count**: 1 object  
**Purpose**: Physical substation definition

**Reference Properties:**
- `Substation.Region` → SubGeographicalRegion

**Inherited Properties:**
- `IdentifiedObject.name` - Substation name - String

### FossilFuel (Fuel Specifications)
**File**: Equipment Core (EQ)  
**Count**: 2 objects  
**Purpose**: Generator fuel specifications

**Reference Properties:**
- `FossilFuel.ThermalGeneratingUnit` → ThermalGeneratingUnit
- `fossilFuelType` → FuelType (enumeration - gas, coal, oil, etc.)

**Inherited Properties:**
- `IdentifiedObject.name` - Fuel name - String

### Geographic Organization Classes

#### GeographicalRegion
**Count**: 1 object  
**Inherited Properties:**
- `IdentifiedObject.name` - Region name - String

#### SubGeographicalRegion  
**Count**: 1 object  
**Reference Properties:**
- `SubGeographicalRegion.Region` → GeographicalRegion
**Inherited Properties:**
- `IdentifiedObject.name` - Sub-region name - String

### Load Organization Classes

#### LoadResponseCharacteristic
**Count**: 1 object  
**Literal Properties:**
- `exponentModel` - Use exponent model - Bool
- `pVoltageExponent` - Active power voltage exponent - Float64
- `qVoltageExponent` - Reactive power voltage exponent - Float64
**Inherited Properties:**
- `IdentifiedObject.name` - Characteristic name - String

#### ConformLoadGroup
**Count**: 1 object  
**Reference Properties:**
- `LoadGroup.SubLoadArea` → SubLoadArea
**Inherited Properties:**
- `IdentifiedObject.name` - Group name - String

#### LoadArea / SubLoadArea
**Count**: 1 each  
**Reference Properties:**
- `SubLoadArea.LoadArea` → LoadArea
**Inherited Properties:**
- `IdentifiedObject.name` - Area name - String

---

## Steady State Hypothesis File (SSH) - Operational Data

### ThermalGeneratingUnit (Generator Operation)
**File**: Steady State Hypothesis (SSH)  
**Count**: 2 objects (references to EQ objects)  
**Purpose**: Operational parameters for generators

**Literal Properties:**
- `normalPF` - Normal power factor - Float64

### RegulatingControl (Control Settings)
**File**: Steady State Hypothesis (SSH)  
**Count**: 2 objects (references to EQ objects)  
**Purpose**: Control system operational settings

**Literal Properties:**
- `discrete` - Discrete control mode - Bool
- `enabled` - Control enabled status - Bool
- `targetValue` - Target value (kV or MVAr) - Float64

**Reference Properties:**
- `targetValueUnitMultiplier` → UnitMultiplier (enumeration - k for kilo)

### ConformLoad (Load Operation)
**File**: Steady State Hypothesis (SSH)  
**Count**: 1 object (reference to EQ object)  
**Purpose**: Load operational values

**Literal Properties:**
- `p` - Active power (MW) - Float64
- `q` - Reactive power (MVAr) - Float64

### Terminal (Connection States)
**File**: Steady State Hypothesis (SSH)  
**Count**: 15 objects (references to EQ objects)  
**Purpose**: Terminal connection status

**Literal Properties:**
- `connected` - Connection status - Bool

---

## Topology File (TP) - Network Connectivity

### TopologicalNode (Electrical Nodes)
**File**: Topology (TP)  
**Count**: 3 objects  
**Purpose**: Electrical connection points in the network

**No specific properties** - Acts as connection point for terminals

### Terminal (Connectivity)
**File**: Topology (TP)  
**Count**: 15 objects (references to EQ objects)  
**Purpose**: Maps terminals to topological nodes

**Reference Properties:**
- `Terminal.TopologicalNode` → TopologicalNode

---

## State Variables File (SV) - Power Flow Results

### SvPowerFlow (Power Flow Results)
**File**: State Variables (SV)  
**Count**: 9 objects  
**Purpose**: Power flow at terminals

**Literal Properties:**
- `p` - Active power flow (MW) - Float64
- `q` - Reactive power flow (MVAr) - Float64

**Reference Properties:**
- `SvPowerFlow.Terminal` → Terminal

### SvVoltage (Voltage Results)
**File**: State Variables (SV)  
**Count**: 3 objects  
**Purpose**: Voltage at topological nodes

**Literal Properties:**
- `v` - Voltage magnitude (kV) - Float64
- `angle` - Voltage angle (radians) - Float64

**Reference Properties:**
- `SvVoltage.TopologicalNode` → TopologicalNode

### TopologicalIsland (System State)
**File**: State Variables (SV)  
**Count**: 1 object  
**Purpose**: Connected electrical island

**No specific properties** - Represents connected system portion

---

## Diagram Layout File (DL) - Visual Representation

### Diagram (Diagram Definition)
**File**: Diagram Layout (DL)  
**Count**: 1 object  
**Purpose**: Diagram definition and orientation

**Reference Properties:**
- `orientation` → OrientationKind (enumeration - positive/negative)

**Inherited Properties:**
- `IdentifiedObject.name` - Diagram name - String

### DiagramObject (Visual Elements)
**File**: Diagram Layout (DL)  
**Count**: 6 objects  
**Purpose**: Visual representation of power system components

**Literal Properties:**
- `rotation` - Rotation angle (degrees) - Float64

**Reference Properties:**
- `DiagramObject.Diagram` → Diagram
- `DiagramObject.IdentifiedObject` → Equipment (references EQ objects)

**Inherited Properties:**
- `IdentifiedObject.name` - Object name - String

### DiagramObjectPoint (Positioning)
**File**: Diagram Layout (DL)  
**Count**: 11 objects  
**Purpose**: Coordinate points for visual elements

**Reference Properties:**
- `DiagramObjectPoint.DiagramObject` → DiagramObject

---

## Geographical Location File (GL) - Geographic Data

### CoordinateSystem (Spatial Reference)
**File**: Geographical Location (GL)  
**Count**: 1 object  
**Purpose**: Coordinate system definition

**Inherited Properties:**
- `IdentifiedObject.name` - System name - String

### Location (Geographic Positions)
**File**: Geographical Location (GL)  
**Count**: 3 objects  
**Purpose**: Geographic location of equipment

**Inherited Properties:**
- `IdentifiedObject.name` - Location name - String

### PositionPoint (Coordinates)
**File**: Geographical Location (GL)  
**Count**: 3 objects  
**Purpose**: Specific coordinate points

**No documented properties in this dataset**

---

## Dynamics File (DY) - Dynamic Behavior

### EnergyConsumer (Dynamic Load)
**File**: Dynamics (DY)  
**Count**: 1 object  
**Purpose**: Dynamic load model

**Inherited Properties:**
- `IdentifiedObject.name` - Consumer name - String

### LoadAggregate (Aggregated Load)
**File**: Dynamics (DY)  
**Count**: 1 object  
**Purpose**: Aggregate load model

**Inherited Properties:**
- `IdentifiedObject.name` - Aggregate name - String

### LoadStatic (Static Load)
**File**: Dynamics (DY)  
**Count**: 1 object  
**Purpose**: Static load component

**Inherited Properties:**
- `IdentifiedObject.name` - Load name - String

### SynchronousMachineTimeConstantReactance (Generator Dynamics)
**File**: Dynamics (DY)  
**Count**: 2 objects  
**Purpose**: Generator dynamic parameters with time constants and reactances

**Inherited Properties:**
- `IdentifiedObject.name` - Machine name - String

---

## Data Type Summary for Julia Implementation

### Common Data Types:
- **String**: Names, descriptions, identifiers
- **Float64**: Electrical parameters, power values, voltages, angles
- **Int64**: Sequence numbers, counts
- **Bool**: Status flags, enable/disable states
- **CIMReference**: References to other CIM objects (rdf:resource)

### Reference Patterns:
- **Equipment→Container**: All equipment references its container (VoltageLevel, Substation)
- **Terminal→Equipment**: Every terminal belongs to one piece of equipment
- **Limit→LimitSet→Terminal**: Hierarchical limit structure
- **StateVariable→NetworkElement**: Results reference network topology
- **Visual→Equipment**: Diagram elements reference physical equipment

### Inheritance Hierarchy:
```
IdentifiedObject (base)
├── Equipment
│   ├── ConductingEquipment
│   │   ├── ACLineSegment
│   │   ├── BusbarSection  
│   │   └── EnergyConsumer (ConformLoad)
│   └── GeneratingUnit (ThermalGeneratingUnit)
└── PowerSystemResource
    ├── Terminal
    ├── BaseVoltage
    └── TopologicalNode
```

This structure provides the complete property mapping needed for Julia CIM parser implementation.