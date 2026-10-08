extends RefCounted

const STEP_SECONDS := 0.02
enum Op { NONE, BUTTON, LAMP, AND, OR, XOR, XNOR, NAND, NOR, NOT, CONST, CLOCK, EDGE, SR, DFF, JK, TFF, DELAY, CLOCK_IN, CLOCK_OUT }
const OPERATIONS := {
	"MP/IO/BUTTON": Op.BUTTON, "MP/IO/LAMP": Op.LAMP,
	"MP/Logic/AND": Op.AND, "MP/Logic/OR": Op.OR, "MP/Logic/XOR": Op.XOR,
	"MP/Logic/XNOR": Op.XNOR, "MP/Logic/NAND": Op.NAND, "MP/Logic/NOR": Op.NOR,
	"MP/Logic/NOT": Op.NOT, "MP/Logic/CONST": Op.CONST, "MP/Logic/CLOCK": Op.CLOCK,
	"MP/Logic/EDGE": Op.EDGE, "MP/Logic/SR": Op.SR, "MP/Logic/DFF": Op.DFF,
	"MP/Logic/JK": Op.JK, "MP/Logic/TFF": Op.TFF, "GUNSAW/DELAY": Op.DELAY,
	"EDITOR/CLOCK_IN": Op.CLOCK_IN, "EDITOR/CLOCK_OUT": Op.CLOCK_OUT
}

var dirty := true
var gate_count := -1
var wire_count := -1
var _gates: Array = []
var _ops := PackedByteArray()
var _inputs := PackedByteArray()
var _previous := PackedByteArray()
var _next := PackedByteArray()
var _outputs := PackedByteArray()
var _memory := PackedByteArray()
var _parameters := PackedByteArray()
var _states := PackedByteArray()
var _button_used := PackedByteArray()
var _delay_active := PackedByteArray()
var _clock_high := PackedByteArray()
var _elapsed := PackedFloat32Array()
var _periods := PackedFloat32Array()
var _delay_remaining := PackedFloat32Array()
var _delay_duration := PackedFloat32Array()
var _delivery_epochs := PackedInt64Array()
var _routes: Array[PackedInt32Array] = []
var _native_routes: Array[PackedInt32Array] = []
var _groups: Array[PackedInt32Array] = []
var _memory_gates := PackedInt32Array()
var _delays := PackedInt32Array()
var _buttons := PackedInt32Array()
var _clock_inputs := PackedInt32Array()
var _clock_outputs := PackedInt32Array()
var _epoch := 0
var _step_seconds: float = PackedFloat32Array([STEP_SECONDS])[0]

static func reset(gates: Array) -> void:
	for gate in gates:
		gate["inputs"].fill(false)
		gate["outputs"].fill(false)
		gate["previous_inputs"].fill(false)
		gate["pulse_pending"] = false
		gate["memory"] = int(gate.get("gunsaw_data", {}).get("initialQ", 0)) != 0
		gate["state"] = true
		for key in ["simulation_clock_elapsed", "simulation_clock_high", "simulation_delay_remaining", "simulation_button_used"]:
			gate.erase(key)

func compile(gates: Array, wires: Array, original_wire_count: int) -> void:
	_gates = gates
	gate_count = gates.size()
	wire_count = original_wire_count
	_ops.resize(gate_count)
	_inputs.resize(gate_count)
	_previous.resize(gate_count)
	_next.resize(gate_count)
	_outputs.resize(gate_count)
	_memory.resize(gate_count)
	_parameters.resize(gate_count)
	_states.resize(gate_count)
	_button_used.resize(gate_count)
	_delay_active.resize(gate_count)
	_clock_high.resize(gate_count)
	_elapsed.resize(gate_count)
	_periods.resize(gate_count)
	_delay_remaining.resize(gate_count)
	_delay_duration.resize(gate_count)
	_delivery_epochs.resize(gate_count)
	_delivery_epochs.fill(-1)
	_routes.clear()
	_routes.resize(gate_count * 2)
	_native_routes.clear()
	_native_routes.resize(gate_count * 2)
	_groups.clear()
	_groups.resize(Op.size())
	_memory_gates.clear()
	_delays.clear()
	_buttons.clear()
	_clock_inputs.clear()
	_clock_outputs.clear()
	for i in range(gate_count):
		var gate: Dictionary = gates[i]
		var data: Dictionary = gate.get("gunsaw_data", {})
		var op: int = OPERATIONS.get(gate["type_id"], Op.NONE)
		_ops[i] = op
		_groups[op].append(i)
		if op >= Op.SR and op <= Op.TFF:
			_memory_gates.append(i)
		_inputs[i] = mask(gate["inputs"])
		_previous[i] = mask(gate["previous_inputs"])
		_outputs[i] = mask(gate["outputs"])
		_memory[i] = int(gate["memory"])
		_states[i] = int(gate["state"])
		_button_used[i] = int(gate.get("simulation_button_used", false))
		_delay_active[i] = int(gate.has("simulation_delay_remaining"))
		_clock_high[i] = int(gate.get("simulation_clock_high", int(data.get("initialHigh", 0)) != 0))
		_elapsed[i] = float(gate.get("simulation_clock_elapsed", 0.0))
		_periods[i] = maxf(_step_seconds, float(data.get("period", 1.0)) * 0.5)
		_delay_remaining[i] = float(gate.get("simulation_delay_remaining", 0.0))
		_delay_duration[i] = float(data.get("delay", 0.0))
		_parameters[i] = 0
		match op:
			Op.BUTTON:
				_parameters[i] = int(int(gate.get("gunsaw_part", {}).get("activId", 0)) > 0)
				_buttons.append(i)
			Op.LAMP:
				var ids: Array = gate.get("gunsaw_input_ids", [])
				_parameters[i] = int(ids.is_empty() or int(ids[0]) > 0)
			Op.CONST: _parameters[i] = int(int(data.get("value", 1)) != 0)
			Op.EDGE:
				var mode := int(data.get("mode", 2))
				_parameters[i] = mode if mode >= 0 and mode <= 2 else 255
			Op.DELAY: _delays.append(i)
			Op.CLOCK_IN: _clock_inputs.append(i)
			Op.CLOCK_OUT: _clock_outputs.append(i)
	for wire in wires:
		var slot := int(wire["from_gate"]) * 2 + int(wire["from_port"])
		var target := int(wire["to_gate"])
		var destination := (target << 2) | int(wire["to_port"])
		if _ops[target] == Op.LAMP or _ops[target] == Op.DELAY:
			_native_routes[slot].append(destination)
		else:
			_routes[slot].append(destination)
	dirty = false

func advance() -> void:
	_next.fill(0)
	_outputs.fill(0)
	for i in _groups[Op.AND]:
		_outputs[i] = int((_inputs[i] & 3) == 3)
	for i in _groups[Op.OR]:
		_outputs[i] = int((_inputs[i] & 3) != 0)
	for i in _groups[Op.XOR]:
		var inputs: int = _inputs[i]
		_outputs[i] = (inputs ^ (inputs >> 1)) & 1
	for i in _groups[Op.XNOR]:
		var inputs: int = _inputs[i]
		_outputs[i] = 1 ^ ((inputs ^ (inputs >> 1)) & 1)
	for i in _groups[Op.NAND]:
		_outputs[i] = int((_inputs[i] & 3) != 3)
	for i in _groups[Op.NOR]:
		_outputs[i] = int((_inputs[i] & 3) == 0)
	for i in _groups[Op.NOT]:
		_outputs[i] = 1 ^ (_inputs[i] & 1)
	for i in _groups[Op.CONST]:
		_outputs[i] = _parameters[i]
	for i in _groups[Op.CLOCK]:
		_elapsed[i] += _step_seconds
		while _elapsed[i] >= _periods[i]:
			_elapsed[i] -= _periods[i]
			_clock_high[i] ^= 1
		_outputs[i] = _clock_high[i]
	for i in _groups[Op.EDGE]:
		var inputs: int = _inputs[i]
		if (inputs ^ _previous[i]) & 1:
			var mode: int = _parameters[i]
			_outputs[i] = int(mode == 2 or (mode == 0 and (inputs & 1) != 0) or (mode == 1 and (inputs & 1) == 0))
	for i in _groups[Op.SR]:
		var inputs: int = _inputs[i] & 3
		if inputs == 1:
			_memory[i] = 1
		elif inputs == 2:
			_memory[i] = 0
	for i in _groups[Op.DFF]:
		var inputs: int = _inputs[i]
		if (inputs & 2) != 0 and (_previous[i] & 2) == 0:
			_memory[i] = inputs & 1
	for i in _groups[Op.JK]:
		var inputs: int = _inputs[i]
		if (inputs & 4) != 0 and (_previous[i] & 4) == 0:
			if (inputs & 3) == 3:
				_memory[i] ^= 1
			elif inputs & 3:
				_memory[i] = inputs & 1
	for i in _groups[Op.TFF]:
		if (_inputs[i] & 3) == 3 and (_previous[i] & 2) == 0:
			_memory[i] ^= 1
	for i in _memory_gates:
		var result: int = _memory[i]
		_outputs[i] = result | ((1 ^ result) << 1)
	for i in _buttons:
		var gate: Dictionary = _gates[i]
		var pulse: bool = gate["pulse_pending"]
		_outputs[i] = int(pulse and not _button_used[i])
		if _outputs[i] and _parameters[i]:
			_button_used[i] = 1
		gate["pulse_pending"] = false
	_epoch += 1
	for i in range(gate_count):
		var outputs: int = _outputs[i]
		if outputs & 1:
			deliver(i * 2)
		if outputs & 2:
			deliver(i * 2 + 1)
	for i in _delays:
		if not _delay_active[i]:
			continue
		_delay_remaining[i] -= _step_seconds
		if _delay_remaining[i] < 0:
			_delay_active[i] = 0
			_outputs[i] = 1
			_epoch += 1
			deliver(i * 2)
	var spare := _previous
	_previous = _inputs
	_inputs = _next
	_next = spare
	var clock_bus := 0
	for i in _clock_inputs:
		clock_bus |= _inputs[i] & 1
	for i in _clock_outputs:
		_outputs[i] = clock_bus

func deliver(slot: int) -> void:
	for destination in _routes[slot]:
		_next[destination >> 2] |= 1 << (destination & 3)
	for destination in _native_routes[slot]:
		var gate := destination >> 2
		_next[gate] |= 1 << (destination & 3)
		if _delivery_epochs[gate] == _epoch:
			continue
		_delivery_epochs[gate] = _epoch
		if _ops[gate] == Op.LAMP:
			_states[gate] ^= _parameters[gate]
		else:
			_delay_remaining[gate] = _delay_duration[gate]
			_delay_active[gate] = 1

func output_high(gate: int, port: int) -> bool:
	return (_outputs[gate] & (1 << port)) != 0

func sync_gate(index: int) -> void:
	if dirty:
		return
	var gate: Dictionary = _gates[index]
	for port in range(gate["inputs"].size()):
		gate["inputs"][port] = (_inputs[index] & (1 << port)) != 0
		gate["previous_inputs"][port] = (_previous[index] & (1 << port)) != 0
	for port in range(gate["outputs"].size()):
		gate["outputs"][port] = (_outputs[index] & (1 << port)) != 0
	gate["memory"] = _memory[index] != 0
	gate["state"] = _states[index] != 0
	match _ops[index]:
		Op.CLOCK:
			gate["simulation_clock_elapsed"] = _elapsed[index]
			gate["simulation_clock_high"] = _clock_high[index] != 0
		Op.DELAY:
			if _delay_active[index]:
				gate["simulation_delay_remaining"] = _delay_remaining[index]
			else:
				gate.erase("simulation_delay_remaining")
		Op.BUTTON:
			gate["simulation_button_used"] = _button_used[index] != 0

func sync_all() -> void:
	if not dirty:
		for i in range(gate_count):
			sync_gate(i)

static func mask(values: Array) -> int:
	var result := 0
	for i in range(values.size()):
		if values[i]:
			result |= 1 << i
	return result
