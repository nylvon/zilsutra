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
            else => @compileError(std.fmt.comptimePrint("Register bit width '{}' is not implemented! " ++
                "Please use either of the following for now: [64, 32, 16, 8]", .{definition.*.bit_width})),
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

// Contains one of the possible results of a duplicate finding function
// Inside it are the first two indices inside an array that were found
// to have matching struct string fields
pub const DuplicateResult = struct {
    index_1: usize,
    index_2: usize,
};

// Creates a function that finds duplicates based on a function given that evaluates
// whether any two of the elements of the array can be considered duplicates of eachother
pub fn CreateDuplicateFindingFunction(base_array_type: type, matching_function: fn (a: base_array_type, b: base_array_type) bool) fn (array: []const base_array_type) ?DuplicateResult {
    return struct {
        pub fn FindDuplicates(array: []const base_array_type) ?DuplicateResult {
            // NOTE: This is a very brute way of doing it
            // We should change this to use hash maps instead of this O(n^2) search
            // TODO: Rewrite this with hash maps.
            for (0..array.len) |i| {
                for (0..array.len) |j| {
                    if (i != j) {
                        if (matching_function(array[i], array[j])) {
                            return DuplicateResult{ .index_1 = i, .index_2 = j };
                        }
                    }
                }
            }
            // If we're here, we went through the whole list and found no duplicates
            return null;
        }
    }.FindDuplicates;
}

// This evaluates whether two registers are duplicates of eachother fully
pub fn RegisterMatchingFunction(a: *const RegisterDefinition, b: *const RegisterDefinition) bool {
    return std.mem.eql(u8, a.hardware_name, b.hardware_name) and (a.bit_width == b.bit_width);
}

// This evaluates whether two registers are duplicates of eachother name-wise
pub fn RegisterNameMatchingFunction(a: *const RegisterDefinition, b: *const RegisterDefinition) bool {
    return std.mem.eql(u8, a.hardware_name, b.hardware_name);
}

// This evaluates whether two instructions are duplicates of eachother name-wise
pub fn InstructionNameMatchingFunction(a: *const InstructionDefinition, b: *const InstructionDefinition) bool {
    return std.mem.eql(u8, a.hardware_name, b.hardware_name);
}

// These can be used to find duplicates
pub const FindRegisterDuplicates = CreateDuplicateFindingFunction(*const RegisterDefinition, RegisterNameMatchingFunction);
pub const FindInstructionDuplicates = CreateDuplicateFindingFunction(*const InstructionDefinition, InstructionNameMatchingFunction);

// This is used to construct instructions
// This is pretty architecture-dependent
// But you could use it without an architecture if desired
pub const InstructionDefinition = struct {
    hardware_name: []const u8,
    involved_registers: []const *const RegisterDefinition,
};

// This creates a function that will take in an array of elements of type given by source type
// and execute the transform function over them, creating struct fields, and returning
// a struct type info object with the struct fields set to those created.
pub fn CreateTableStructInfoDefiningFunction( //
    source_type: type,
    transform_function: fn (source: source_type) std.builtin.Type.StructField,
) fn (array: []const source_type) std.builtin.Type.Struct {
    return struct {
        pub fn CreateTableStructInfo(array: []const source_type) std.builtin.Type.Struct {
            // Exit early if no types are given
            if (array.len == 0) {
                return std.builtin.Type.Struct{
                    .fields = &.{},
                    .decls = &.{},
                    .is_tuple = false,
                    .layout = .auto,
                };
            }

            // Otherwise, construct the struct fields
            var table_struct_fields: [array.len]std.builtin.Type.StructField = undefined;

            for (0..array.len) |i| {
                table_struct_fields[i] = transform_function(array[i]);
            }

            return std.builtin.Type.Struct{
                .fields = &table_struct_fields,
                .decls = &.{},
                .is_tuple = false,
                .layout = .auto,
            };
        }
    }.CreateTableStructInfo;
}

// Given a certain source type, an array of elements of that type, and a function that can
// map any of the elements of the array into a struct field, this will return a struct type that has
// the fields given by the transform function executed with source array as the argument
pub fn CreateTableStructType( //
    comptime source_type: type,
    comptime source_array: []const source_type,
    comptime transform_function: fn (source: source_type) std.builtin.Type.StructField,
) type {
    const specific_table_struct_info_defining_function = CreateTableStructInfoDefiningFunction(source_type, transform_function);
    return @Type(std.builtin.Type{ .@"struct" = specific_table_struct_info_defining_function(source_array) });
}

// Converts a register definition to a struct field
// with the struct field name set to the hardware name
// and the struct field type set to the type associated
// with the register definition.
pub fn RegisterToValueStructField(source: *const RegisterDefinition) std.builtin.Type.StructField {
    const built_register = BuildRegister(source);
    return std.builtin.Type.StructField{
        .name = @ptrCast(source.*.hardware_name),
        .type = built_register,
        .alignment = @alignOf(built_register),
        .default_value = null,
        .is_comptime = false,
    };
}

// Converts a register definition to a struct field
// with the struct field name set to the hardware name
// and the struct field type set to a pointer to an object
// of the type associated with the register definition.
pub fn RegisterToPointerStructField(source: *const RegisterDefinition) std.builtin.Type.StructField {
    const built_register = BuildRegister(source);
    return std.builtin.Type.StructField{
        .name = @ptrCast(source.*.hardware_name),
        .type = *built_register,
        .alignment = @alignOf(*built_register),
        .default_value = null,
        .is_comptime = false,
    };
}

test "Create Table Struct Info Defining Function - Register Definition" {
    const register_definition_1 = RegisterDefinition{ .hardware_name = "RA", .bit_width = 16 };
    const register_definition_2 = RegisterDefinition{ .hardware_name = "RB", .bit_width = 8 };
    const register_definition_3 = RegisterDefinition{ .hardware_name = "RC", .bit_width = 32 };
    const register_definition_4 = RegisterDefinition{ .hardware_name = "RD", .bit_width = 64 };
    const register_definition_5 = RegisterDefinition{ .hardware_name = "PC", .bit_width = 64 };
    const example_register_definitions = [_]*const RegisterDefinition{ //
        &register_definition_1,
        &register_definition_2,
        &register_definition_3,
        &register_definition_4,
        &register_definition_5,
    };

    const ExpectedRegisterValueTableType = struct {
        RA: BuildRegister(&register_definition_1),
        RB: BuildRegister(&register_definition_2),
        RC: BuildRegister(&register_definition_3),
        RD: BuildRegister(&register_definition_4),
        PC: BuildRegister(&register_definition_5),
    };

    const RegisterValueTableType = CreateTableStructType(*const RegisterDefinition, &example_register_definitions, RegisterToValueStructField);
    const RegisterPointerTableType = CreateTableStructType(*const RegisterDefinition, &example_register_definitions, RegisterToPointerStructField);

    comptime {
        const ExpectedValueTypeInfo = @typeInfo(ExpectedRegisterValueTableType).@"struct";
        const ActualValueTypeInfo = @typeInfo(RegisterValueTableType).@"struct";
        const ActualPointerTypeInfo = @typeInfo(RegisterPointerTableType).@"struct";

        try expect(ExpectedValueTypeInfo.fields.len == ActualValueTypeInfo.fields.len);
        try expect(ExpectedValueTypeInfo.fields.len == ActualPointerTypeInfo.fields.len);

        for (0..ExpectedValueTypeInfo.fields.len) |i| {
            try expect(std.mem.eql(u8, ExpectedValueTypeInfo.fields[i].name, ActualValueTypeInfo.fields[i].name));
            try expect(ExpectedValueTypeInfo.fields[i].type == ActualValueTypeInfo.fields[i].type);
            try expect(std.mem.eql(u8, ExpectedValueTypeInfo.fields[i].name, ActualPointerTypeInfo.fields[i].name));
            try expect(ExpectedValueTypeInfo.fields[i].type != ActualPointerTypeInfo.fields[i].type);
            try expect(*ActualValueTypeInfo.fields[i].type == ActualPointerTypeInfo.fields[i].type);
        }
    }
}

// Creates a struct type that has fields named according to the registers
// defined by the involved register definitions, with the types being
// the ones associated with the register definitions or pointers to them
// depending on whether a pointer form is desired.
pub fn RegisterTableType( //
    comptime involved_register_definitions: []const *const RegisterDefinition,
    comptime field_type_form: enum { Value, Pointer },
) type {
    comptime {
        // If no registers are involved, then there's no need to create
        // a big type based around them.
        if (involved_register_definitions.len == 0) {
            return void;
        }

        // Check for duplicates
        if (FindRegisterDuplicates(involved_register_definitions)) |duplicate_info| {
            @compileError(std.fmt.comptimePrint( //
                "Registers with the same hardware name found at indices '{}' and '{}'!", .{ duplicate_info.index_1, duplicate_info.index_2 }));
        }

        // Create the type and return it
        switch (field_type_form) {
            .Value => return CreateTableStructType(*const RegisterDefinition, involved_register_definitions, RegisterToValueStructField),
            .Pointer => return CreateTableStructType(*const RegisterDefinition, involved_register_definitions, RegisterToPointerStructField),
        }
    }
}

test "Register Table Type - Manual" {
    const register_definition_1 = RegisterDefinition{ .hardware_name = "RA", .bit_width = 16 };
    const register_definition_2 = RegisterDefinition{ .hardware_name = "RB", .bit_width = 8 };
    const register_definition_3 = RegisterDefinition{ .hardware_name = "RC", .bit_width = 32 };
    const register_definition_4 = RegisterDefinition{ .hardware_name = "RD", .bit_width = 64 };
    const register_definition_5 = RegisterDefinition{ .hardware_name = "PC", .bit_width = 64 };
    const example_register_definitions = [_]*const RegisterDefinition{ //
        &register_definition_1,
        &register_definition_2,
        &register_definition_3,
        &register_definition_4,
        &register_definition_5,
    };

    const example_register_selection_type = RegisterTableType(&example_register_definitions, .Pointer);

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
pub fn BuildInstruction(comptime definition: *const InstructionDefinition) type {
    const register_selection_type = RegisterTableType(definition.involved_registers, .Pointer);

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

// Converts a register definition to a struct field
// with the struct field name set to the hardware name
// and the struct field type set to the type associated
// with the instruction definition.
pub fn InstructionToStructField(source: *const InstructionDefinition) std.builtin.Type.StructField {
    const built_instruction = BuildInstruction(source);
    return std.builtin.Type.StructField{
        .name = @ptrCast(source.*.hardware_name),
        .type = built_instruction,
        .alignment = @alignOf(built_instruction),
        .default_value = null,
        .is_comptime = false,
    };
}

// Creates a struct type that has fields named according to the instructions
// defined by the involved instruction definitions, with the types being
// the ones associated with the instruction definitions
pub fn InstructionTableType(comptime involved_instruction_definitions: []const *const InstructionDefinition) type {
    comptime {
        // If no instructions are involved, then there's no need to create
        // a big type based around them.
        if (involved_instruction_definitions.len == 0) {
            return void;
        }

        // Check for duplicates
        if (FindInstructionDuplicates(involved_instruction_definitions)) |duplicate_info| {
            @compileError(std.fmt.comptimePrint( //
                "Instructions with the same hardware name found at indices '{}' and '{}'!", .{ duplicate_info.index_1, duplicate_info.index_2 }));
        }

        // Create the type and return it
        return CreateTableStructType(*const InstructionDefinition, involved_instruction_definitions, InstructionToStructField);
    }
}

test "Build Instruction" {
    const register_definition_1 = RegisterDefinition{ .hardware_name = "RA", .bit_width = 8 };
    const register_definition_2 = RegisterDefinition{ .hardware_name = "RB", .bit_width = 8 };

    const register_definitions = [_]*const RegisterDefinition{ //
        &register_definition_1,
        &register_definition_2,
    };

    const register_sample_type = RegisterTableType(&register_definitions, .Pointer);

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

    const example_instruction_type = BuildInstruction(&instruction_definition);

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

// This is used to construct actual architectures
// Architectures contain specific instructions and registers
pub const ArchitectureDefinition = struct {
    register_definitions: []const *const RegisterDefinition,
    instruction_definitions: []const *const InstructionDefinition,
};

pub fn BuildArchitecture(comptime architecture_definition: *const ArchitectureDefinition) type { //
    // Make sure that there's no duplicates in the registers in the architecture itself
    if (FindRegisterDuplicates(architecture_definition.register_definitions)) |duplicate_info| {
        @compileError(std.fmt.comptimePrint( //
            "Registers with the same hardware name found at indices '{}' and '{}'!", .{ duplicate_info.index_1, duplicate_info.index_2 }));
    }
    // Same for instructions
    if (FindInstructionDuplicates(architecture_definition.instruction_definitions)) |duplicate_info| {
        @compileError(std.fmt.comptimePrint( //
            "Instructions with the same hardware name found at indices '{}' and '{}'!", .{ duplicate_info.index_1, duplicate_info.index_2 }));
    }

    // Make sure that no instruction uses a register that is not part of the architecture
    // Because... how would it use something that it doesn't have access to?
    for (0..architecture_definition.instruction_definitions.len) |i| {
        const current_instruction_definition = architecture_definition.instruction_definitions[i];

        // This is not great performance-wise, but it's compile-time only
        // and usually instructions don't involve that many registers.
        // We will optimize it when we will need to, with hash maps.
        for (0..current_instruction_definition.involved_registers.len) |j| {
            const current_instruction_register = current_instruction_definition.involved_registers[j];

            // Initially assume there is no register involved that's not part of the architecture
            var foundRegister: bool = false;

            // Then search for it
            for (0..architecture_definition.register_definitions.len) |k| {
                const current_architecture_register = architecture_definition.register_definitions[k];

                if (RegisterMatchingFunction(current_instruction_register, current_architecture_register)) {
                    // If we found a match, we can stop searching
                    foundRegister = true;
                    break;
                }
            }

            // If we're here, check if we found any
            if (!foundRegister) {
                // If we found a match, we're okay, go to the next one
                // But if we did not, we should crash out
                @compileError(std.fmt.comptimePrint( //
                    "Instruction '{s}' has a register involved" ++
                    "in its operation '{s}' that was not found in any of the architecture's registers!", //
                    .{ current_instruction_definition.hardware_name, current_instruction_register.hardware_name }));
            }
        }
    }

    // If we're here, all instructions and registers are okay

    const register_storage_type = RegisterTableType(architecture_definition.register_definitions, .Value);
    const instruction_storage_type = InstructionTableType(architecture_definition.instruction_definitions);

    // This type will get updated to offer ease-of-use functions to access registers and instructions
    return struct { registers: register_storage_type, instructions: instruction_storage_type };
}

test "Build Architecture - Manual" {
    // We'll build a minimal 2 register architecture, with 4 instructions, as a proof of concept
    const register_bit_width = 8;
    const register_definition_a = RegisterDefinition{ .hardware_name = "RA", .bit_width = register_bit_width };
    const register_definition_b = RegisterDefinition{ .hardware_name = "RB", .bit_width = register_bit_width };

    // This will swap our registers RA and RB
    const instruction_definition_swap = InstructionDefinition{ //
        .hardware_name = "SWAP",
        .involved_registers = &[_]*const RegisterDefinition{ //
            &register_definition_a,
            &register_definition_b,
        },
    };

    // This will increment RA by 1
    const instruction_definition_inc_a = InstructionDefinition{ //
        .hardware_name = "INCA",
        .involved_registers = &[_]*const RegisterDefinition{ //
        &register_definition_a},
    };

    // This will decrement RA by 1
    const instruction_definition_dec_a = InstructionDefinition{ //
        .hardware_name = "DECA",
        .involved_registers = &[_]*const RegisterDefinition{ //
        &register_definition_a},
    };

    // This will add RA and RB and store them in RA
    const instruction_definition_add = InstructionDefinition{ //
        .hardware_name = "ADD",
        .involved_registers = &[_]*const RegisterDefinition{ //
            &register_definition_a,
            &register_definition_b,
        },
    };

    const example_architecture_definition = ArchitectureDefinition{ //
        .register_definitions = &[_]*const RegisterDefinition{ //
            &register_definition_a,
            &register_definition_b,
        },
        .instruction_definitions = &[_]*const InstructionDefinition{ //
            &instruction_definition_swap,
            &instruction_definition_inc_a,
            &instruction_definition_dec_a,
            &instruction_definition_add,
        },
    };

    const example_architecture_type = BuildArchitecture(&example_architecture_definition);

    const instruction_function_swap = struct {
        pub fn implementation(registers: RegisterTableType(instruction_definition_swap.involved_registers, .Pointer)) anyerror!void {
            // for now we're using the same bits so we'll just do a little trick without caring about bit widths
            const temporary_ghost_register = @field(registers, register_definition_a.hardware_name).bits;
            @field(registers, register_definition_a.hardware_name).bits = @field(registers, register_definition_b.hardware_name).bits;
            @field(registers, register_definition_b.hardware_name).bits = temporary_ghost_register;
        }
    }.implementation;

    const instruction_function_inc_a = struct {
        pub fn implementation(registers: RegisterTableType(instruction_definition_inc_a.involved_registers, .Pointer)) anyerror!void {
            @field(registers, register_definition_a.hardware_name).bits += 1;
        }
    }.implementation;

    const instruction_function_dec_a = struct {
        pub fn implementation(registers: RegisterTableType(instruction_definition_inc_a.involved_registers, .Pointer)) anyerror!void {
            @field(registers, register_definition_a.hardware_name).bits -= 1;
        }
    }.implementation;

    const instruction_function_add = struct {
        pub fn implementation(registers: RegisterTableType(instruction_definition_swap.involved_registers, .Pointer)) anyerror!void {
            @field(registers, register_definition_a.hardware_name).bits += @field(registers, register_definition_b.hardware_name).bits;
        }
    }.implementation;

    var example_architecture = example_architecture_type{ .registers = undefined, .instructions = undefined };

    @field(example_architecture.registers, register_definition_a.hardware_name).bits = 0;
    @field(example_architecture.registers, register_definition_b.hardware_name).bits = 16;

    // swap instruction
    const swap_register_view_type = RegisterTableType(instruction_definition_swap.involved_registers, .Pointer);
    var swap_register_view: swap_register_view_type = undefined;
    @field(swap_register_view, register_definition_a.hardware_name) = &@field(example_architecture.registers, register_definition_a.hardware_name);
    @field(swap_register_view, register_definition_b.hardware_name) = &@field(example_architecture.registers, register_definition_b.hardware_name);
    @field(@field(example_architecture.instructions, instruction_definition_swap.hardware_name), "register_selection") = swap_register_view;
    @field(@field(example_architecture.instructions, instruction_definition_swap.hardware_name), "instruction_function") = &instruction_function_swap;

    // inc a instruction
    const inc_a_register_view_type = RegisterTableType(instruction_definition_inc_a.involved_registers, .Pointer);
    var inc_a_register_view: inc_a_register_view_type = undefined;
    @field(inc_a_register_view, register_definition_a.hardware_name) = &@field(example_architecture.registers, register_definition_a.hardware_name);
    @field(@field(example_architecture.instructions, instruction_definition_inc_a.hardware_name), "register_selection") = inc_a_register_view;
    @field(@field(example_architecture.instructions, instruction_definition_inc_a.hardware_name), "instruction_function") = &instruction_function_inc_a;

    // dec a instruction
    const dec_a_register_view_type = RegisterTableType(instruction_definition_dec_a.involved_registers, .Pointer);
    var dec_a_register_view: dec_a_register_view_type = undefined;
    @field(dec_a_register_view, register_definition_a.hardware_name) = &@field(example_architecture.registers, register_definition_a.hardware_name);
    @field(@field(example_architecture.instructions, instruction_definition_dec_a.hardware_name), "register_selection") = dec_a_register_view;
    @field(@field(example_architecture.instructions, instruction_definition_dec_a.hardware_name), "instruction_function") = &instruction_function_dec_a;

    // add instruction
    const add_register_view_type = RegisterTableType(instruction_definition_add.involved_registers, .Pointer);
    var add_register_view: add_register_view_type = undefined;
    @field(add_register_view, register_definition_a.hardware_name) = &@field(example_architecture.registers, register_definition_a.hardware_name);
    @field(add_register_view, register_definition_b.hardware_name) = &@field(example_architecture.registers, register_definition_b.hardware_name);
    @field(@field(example_architecture.instructions, instruction_definition_add.hardware_name), "register_selection") = add_register_view;
    @field(@field(example_architecture.instructions, instruction_definition_add.hardware_name), "instruction_function") = &instruction_function_add;

    // Initially the registers are:
    // RA = 0, RB = 16
    // We will run this example program:
    // -------- START
    // SWAP
    // INCA
    // SWAP
    // INCA
    // INCA
    // DECA
    // ADD
    // -------- END
    // At the end, the registers should look like:
    // RA = 18, RB = 17

    try expect(@field(example_architecture.registers, register_definition_a.hardware_name).bits == 0);
    try expect(@field(example_architecture.registers, register_definition_b.hardware_name).bits == 16);

    try @field(example_architecture.instructions, instruction_definition_swap.hardware_name).Execute();

    try expect(@field(example_architecture.registers, register_definition_a.hardware_name).bits == 16);
    try expect(@field(example_architecture.registers, register_definition_b.hardware_name).bits == 0);

    try @field(example_architecture.instructions, instruction_definition_inc_a.hardware_name).Execute();

    try expect(@field(example_architecture.registers, register_definition_a.hardware_name).bits == 17);
    try expect(@field(example_architecture.registers, register_definition_b.hardware_name).bits == 0);

    try @field(example_architecture.instructions, instruction_definition_swap.hardware_name).Execute();

    try expect(@field(example_architecture.registers, register_definition_a.hardware_name).bits == 0);
    try expect(@field(example_architecture.registers, register_definition_b.hardware_name).bits == 17);

    try @field(example_architecture.instructions, instruction_definition_inc_a.hardware_name).Execute();

    try expect(@field(example_architecture.registers, register_definition_a.hardware_name).bits == 1);
    try expect(@field(example_architecture.registers, register_definition_b.hardware_name).bits == 17);

    try @field(example_architecture.instructions, instruction_definition_inc_a.hardware_name).Execute();

    try expect(@field(example_architecture.registers, register_definition_a.hardware_name).bits == 2);
    try expect(@field(example_architecture.registers, register_definition_b.hardware_name).bits == 17);

    try @field(example_architecture.instructions, instruction_definition_dec_a.hardware_name).Execute();

    try expect(@field(example_architecture.registers, register_definition_a.hardware_name).bits == 1);
    try expect(@field(example_architecture.registers, register_definition_b.hardware_name).bits == 17);

    try @field(example_architecture.instructions, instruction_definition_add.hardware_name).Execute();

    try expect(@field(example_architecture.registers, register_definition_a.hardware_name).bits == 18);
    try expect(@field(example_architecture.registers, register_definition_b.hardware_name).bits == 17);
}
