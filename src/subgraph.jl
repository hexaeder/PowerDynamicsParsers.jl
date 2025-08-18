export is_terminal

is_class(x, class) = (typeof(x) <: CIMObject) && (x.class_name == class)

is_terminal(t) = is_class(t, "Terminal")

function is_injector(t)
    is_terminal(t) || return false
    eq = t["ConductingEquipment"]
end

BRANCH_CLASSES = ["ACLineSegment"]
function is_lineend(t)
    is_terminal(t) || return false
    eq = t["ConductingEquipment"]
    any(class -> is_class(eq, class), BRANCH_CLASSES)
end

STOP_BACKREF = ["BaseVoltage", "VoltageLevel", "OperationalLimitType", "Substation"]
