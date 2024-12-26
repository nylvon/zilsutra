const std = @import("std");
const testing = std.testing;
const expect = testing.expect;

// This is used to construct actual registers
// These are technically architecture dependent
// But practically, you can use a definition across architectures
pub const RegisterDefinition = struct {
    hardware_name: []const u8,
    bit_width: u32, // 'u32' should be plenty :)
};

// This constructs the register according to the register definition
// The type holds the actual data, it is what a register actually is
// and holds all its related functionality.
pub fn BuildRegister(definition: *const RegisterDefinition) type {
    // Right now, only construct base unsigned integer registers
    return struct {
        //
        bits: switch (definition.*.bit_width) {
            64 => u64,
            32 => u32,
            16 => u16,
            8 => u8,
            else => @compileError(std.fmt.comptimePrint("Bit width '{}' not implemented!", .{definition.*.bit_width})),
        },
    };
}
test "Build Register" {
    const example_register_definition = RegisterDefinition{ .hardware_name = "RA", .bit_width = 16 };
    const example_register_type = comptime BuildRegister(&example_register_definition);
    const example_register = example_register_type{ .bits = 123 };
    try expect(@TypeOf(example_register.bits) == u16);
}

// This constructs many registers, just like 'BuildRegister' does
pub fn BuildRegisters(definitions: []const *const RegisterDefinition) []const type {
    comptime {
        var registers: [definitions.len]type = undefined;

        for (definitions, 0..) |definition, i| {
            registers[i] = BuildRegister(definition);
        }

        return &registers;
    }
}

test "Build Registers" {
    const register_definition_1 = RegisterDefinition{ .hardware_name = "RA", .bit_width = 16 };
    const register_definition_2 = RegisterDefinition{ .hardware_name = "RB", .bit_width = 8 };
    const register_definition_3 = RegisterDefinition{ .hardware_name = "RC", .bit_width = 32 };
    const register_definition_4 = RegisterDefinition{ .hardware_name = "RD", .bit_width = 64 };
    const register_definition_5 = RegisterDefinition{ .hardware_name = "PC", .bit_width = 64 };
    const example_register_definitions = [_]*const RegisterDefinition{
        //
        &register_definition_1,
        &register_definition_2,
        &register_definition_3,
        &register_definition_4,
        &register_definition_5,
    };
    const example_register_types = comptime BuildRegisters(&example_register_definitions);

    inline for (0..example_register_definitions.len) |i| {
        const example_register = example_register_types[i]{ .bits = 1 };
        const expected_register_type = BuildRegister(example_register_definitions[i]);
        const expected_example_register = expected_register_type{ .bits = 1 };
        try expect(@TypeOf(example_register.bits) == @TypeOf(expected_example_register.bits));
    }
}

// This is used to construct instructions
// This is pretty architecture-dependent
// But you could use it without an architecture if desired
pub const InstructionDefinition = struct {
    hardware_name: []const u8,
    involved_registers: []const *const RegisterDefinition,
};

// Creates a struct type that has fields named according to the
// registers defined by 'involved_register_definitions', with the types being
// constant pointers to some actual registers.
pub fn RegisterSelectionType(comptime involved_register_definitions: []const *const RegisterDefinition) type {
    comptime {
        // If no registers are involved, then there's no need to create
        // a big type based around them.
        if (involved_register_definitions.len == 0) {
            return void;
        }

        // These are the types for each register itself
        const defined_register_types = BuildRegisters(involved_register_definitions);

        // The struct will have these fields
        var register_selection_fields: [defined_register_types.len]std.builtin.Type.StructField = undefined;

        // Each field is named after the hardware name in the register definition
        // But it has the actual type given by the register definition
        // Example: "PA" with type "i32"
        for (0..involved_register_definitions.len) |i| {
            register_selection_fields[i] = std.builtin.Type.StructField{ //
                .name = @ptrCast(involved_register_definitions[i].hardware_name),
                .type = *defined_register_types[i],
                .is_comptime = false,
                .default_value = null,
                .alignment = @alignOf(*defined_register_types[i]),
            };
        }

        // This holds the 'definition' of the struct itself, pre-reification
        const register_selection_type_information_struct = std.builtin.Type.Struct{ //
            .fields = &register_selection_fields,
            .decls = &.{},
            .is_tuple = false,
            .layout = .auto,
        };

        const register_selection_type_information = std.builtin.Type{ .@"struct" = register_selection_type_information_struct };

        // This is the real struct, the real type
        const reified_register_selection_type = @Type(register_selection_type_information);

        return reified_register_selection_type;
    }
}

test "Register Selection Type" {
    const register_definition_1 = RegisterDefinition{ .hardware_name = "RA", .bit_width = 16 };
    const register_definition_2 = RegisterDefinition{ .hardware_name = "RB", .bit_width = 8 };
    const register_definition_3 = RegisterDefinition{ .hardware_name = "RC", .bit_width = 32 };
    const register_definition_4 = RegisterDefinition{ .hardware_name = "RD", .bit_width = 64 };
    const register_definition_5 = RegisterDefinition{ .hardware_name = "PC", .bit_width = 64 };
    const example_register_definitions = [_]*const RegisterDefinition{
        //
        &register_definition_1,
        &register_definition_2,
        &register_definition_3,
        &register_definition_4,
        &register_definition_5,
    };

    const example_register_selection_type = RegisterSelectionType(&example_register_definitions);

    const exmaple_register_selection_type_info = @typeInfo(example_register_selection_type).@"struct";

    try expect(exmaple_register_selection_type_info.fields.len == example_register_definitions.len);

    var matching_fields: u32 = 0;
    inline for (0..example_register_definitions.len) |i| {
        var foundIndex: ?u32 = null;
        const expected_register_type = BuildRegister(example_register_definitions[i]);

        inline for (0..exmaple_register_selection_type_info.fields.len) |j| {
            if (std.mem.eql(u8, //
                example_register_definitions[i].*.hardware_name, //
                exmaple_register_selection_type_info.fields[j].name) //
            or ((*expected_register_type) == exmaple_register_selection_type_info.fields[j].type)) {
                foundIndex = j;
            }
        }

        if (foundIndex != null) {
            matching_fields += 1;
        } else {
            return error.NoMatchingField;
        }
    }

    try expect(matching_fields == example_register_definitions.len);
}

// This builds an instruction according to an instruction definition
// The instruction will always hold a function pointer to the actual
// instruction implementation, a function Execute() which will execute it,
// and the hardware name of the instruction as a type-specific declaration
// The Execute() function is the intended public API to be used.
pub fn BuildInstruction(comptime definition: InstructionDefinition) type {
    const register_selection_type = RegisterSelectionType(definition.involved_registers);

    if (register_selection_type == void) {
        // If it's void, then there's no involved registers
        // So return a struct that holds no registers
        return struct {
            instruction_function: *const fn () anyerror!void,

            pub fn Execute(self: @This()) anyerror!void {
                try self.instruction_function();
            }

            pub const HardwareName = definition.hardware_name;
        };
    } else {
        // If it's not void, then there's registers involved
        // So we have to store them alongisde the instruction function
        return struct {
            register_selection: register_selection_type,
            instruction_function: *const fn (register_selection_type) anyerror!void,

            pub fn Execute(self: @This()) anyerror!void {
                try self.instruction_function(self.register_selection);
            }

            pub const HardwareName = definition.hardware_name;
        };
    }
}

test "Build Instruction" {
    const register_definition_1 = RegisterDefinition{ .hardware_name = "RA", .bit_width = 8 };
    const register_definition_2 = RegisterDefinition{ .hardware_name = "RB", .bit_width = 8 };

    const register_definitions = [_]*const RegisterDefinition{
        //
        &register_definition_1,
        &register_definition_2,
    };

    const register_sample_type = RegisterSelectionType(&register_definitions);

    const exampleInstructionFunction = struct {
        pub fn simple_mov(registers: register_sample_type) anyerror!void {
            // NOTE: Do some more compile time checking of bit lengths
            // to see whether we truncate or whether we can fit
            @field(registers, register_definition_1.hardware_name).bits = @field(registers, register_definition_2.hardware_name).bits;
        }
    }.simple_mov;

    const instruction_definition = InstructionDefinition{ //
        .hardware_name = "MOV",
        .involved_registers = &register_definitions,
    };

    const example_instruction_type = BuildInstruction(instruction_definition);

    const register_type_1 = BuildRegister(&register_definition_1);
    const register_type_2 = BuildRegister(&register_definition_2);

    var register_1 = register_type_1{ .bits = 0 };
    var register_2 = register_type_2{ .bits = 16 };

    const register_sample = register_sample_type{ //
        .RA = &register_1,
        .RB = &register_2,
    };

    const example_instruction = example_instruction_type{
        .instruction_function = &exampleInstructionFunction,
        .register_selection = register_sample,
    };

    try expect(register_sample.RA.bits == 0);
    try expect(register_sample.RB.bits == 16);

    try example_instruction.Execute();

    try expect(register_sample.RA.bits == 16);
    try expect(register_sample.RB.bits == 16);
}
