const std = @import("std");

const utils = @import("utils.zig");
const StackFrame = @import("StackFrame.zig");
const primitives = @import("primitives.zig");
const ClassResolver = @import("ClassResolver.zig");

const opcodes = @import("../types/opcodes.zig");
const methods = @import("../types/methods.zig");
const ClassFile = @import("../types/ClassFile.zig");
const attributes = @import("../types/attributes.zig");
const descriptors = @import("../types/descriptors.zig");
const constant_pool = @import("../types/constant_pool.zig");

const Interpreter = @This();

allocator: *std.mem.Allocator,
class_resolver: ClassResolver,

pub fn init(allocator: *std.mem.Allocator, class_resolver: ClassResolver) Interpreter {
    return .{ .allocator = allocator, .class_resolver = class_resolver };
}

pub fn call(self: *Interpreter, path: []const u8, args: anytype) !primitives.PrimitiveValue {
    var class_file = try self.class_resolver.resolve(path[0..std.mem.lastIndexOf(u8, path, ".").?]);
    var method_name = path[std.mem.lastIndexOf(u8, path, ".").? + 1 ..];
    var margs: [std.meta.fields(@TypeOf(args)).len]primitives.PrimitiveValue = undefined;

    var method_info: ?methods.MethodInfo = null;
    for (class_file.methods) |*m| {
        if (!std.mem.eql(u8, m.getName(class_file), method_name)) continue;

        method_info = m.*;
    }

    inline for (std.meta.fields(@TypeOf(args))) |field, i| {
        margs[i] = primitives.PrimitiveValue.fromNative(@field(args, field.name));
    }

    return self.interpret(class_file, method_name, &margs);
}

fn classToDots(allocator: *std.mem.Allocator, class: []const u8) ![]u8 {
    var t = try allocator.alloc(u8, class.len);
    std.mem.copy(u8, t, class);
    for (t) |*v| v.* = if (v.* == '/') '.' else v.*;
    return t;
}

fn interpret(self: *Interpreter, class_file: ClassFile, method_name: []const u8, args: []primitives.PrimitiveValue) anyerror!primitives.PrimitiveValue {
    var descriptor_buf = std.ArrayList(u8).init(self.allocator);
    defer descriptor_buf.deinit();

    for (class_file.methods) |*method| {
        if (!std.mem.eql(u8, method.getName(class_file), method_name)) continue;

        descriptor_buf.shrinkRetainingCapacity(0);
        try utils.formatMethod(self.allocator, class_file, method, descriptor_buf.writer());
        std.log.info("method: {s}", .{descriptor_buf.items});

        // TODO: See descriptors.zig
        for (method.attributes) |*att| {
            var data = try att.readData(self.allocator, class_file);
            std.log.info((" " ** 4) ++ "method attribute: '{s}'", .{att.getName(class_file)});

            switch (data) {
                .code => |code_attribute| {
                    var stack_frame = StackFrame.init(self.allocator, class_file);
                    defer stack_frame.deinit();

                    try stack_frame.local_variables.appendSlice(args);

                    var fbs = std.io.fixedBufferStream(code_attribute.code);
                    var fbs_reader = fbs.reader();

                    var opcode = try opcodes.Operation.readFrom(fbs_reader);

                    // TODO: Refactor this garbage somehow
                    while (true) {
                        std.log.info((" " ** 8) ++ "{s}", .{opcode});
                        // std.log.info((" " ** 8) ++ "{s}", .{s.local_variables.items[0]});
                        switch (opcode) {
                            .iload => |i| try stack_frame.operand_stack.push(.{ .int = stack_frame.local_variables.items[i].int }),
                            .iload_0 => try stack_frame.operand_stack.push(.{ .int = stack_frame.local_variables.items[0].int }),
                            .iload_1 => try stack_frame.operand_stack.push(.{ .int = stack_frame.local_variables.items[1].int }),
                            .iload_2 => try stack_frame.operand_stack.push(.{ .int = stack_frame.local_variables.items[2].int }),
                            .iload_3 => try stack_frame.operand_stack.push(.{ .int = stack_frame.local_variables.items[3].int }),

                            .istore => |i| try stack_frame.setLocalVariable(i, .{ .int = stack_frame.operand_stack.pop().int }),
                            .istore_0 => try stack_frame.setLocalVariable(0, .{ .int = stack_frame.operand_stack.pop().int }),
                            .istore_1 => try stack_frame.setLocalVariable(1, .{ .int = stack_frame.operand_stack.pop().int }),
                            .istore_2 => try stack_frame.setLocalVariable(2, .{ .int = stack_frame.operand_stack.pop().int }),
                            .istore_3 => try stack_frame.setLocalVariable(3, .{ .int = stack_frame.operand_stack.pop().int }),

                            .sipush => |value| try stack_frame.operand_stack.push(.{ .int = value }),
                            .bipush => |value| try stack_frame.operand_stack.push(.{ .int = value }),
                            .ldc => |index| {
                                switch (stack_frame.class_file.resolveConstant(index)) {
                                    .float => |f| try stack_frame.operand_stack.push(.{ .float = @bitCast(f32, f) }),
                                    else => unreachable,
                                }
                            },
                            .iinc => |iinc| stack_frame.local_variables.items[iinc.index].int += iinc.@"const",

                            .fload => |i| try stack_frame.operand_stack.push(.{ .float = stack_frame.local_variables.items[i].float }),
                            .fload_0 => try stack_frame.operand_stack.push(.{ .float = stack_frame.local_variables.items[0].float }),
                            .fload_1 => try stack_frame.operand_stack.push(.{ .float = stack_frame.local_variables.items[1].float }),
                            .fload_2 => try stack_frame.operand_stack.push(.{ .float = stack_frame.local_variables.items[2].float }),
                            .fload_3 => try stack_frame.operand_stack.push(.{ .float = stack_frame.local_variables.items[3].float }),

                            .fstore => |i| try stack_frame.setLocalVariable(i, .{ .float = stack_frame.operand_stack.pop().float }),
                            .fstore_0 => try stack_frame.setLocalVariable(0, .{ .float = stack_frame.operand_stack.pop().float }),
                            .fstore_1 => try stack_frame.setLocalVariable(1, .{ .float = stack_frame.operand_stack.pop().float }),
                            .fstore_2 => try stack_frame.setLocalVariable(2, .{ .float = stack_frame.operand_stack.pop().float }),
                            .fstore_3 => try stack_frame.setLocalVariable(3, .{ .float = stack_frame.operand_stack.pop().float }),

                            .dload => |i| try stack_frame.operand_stack.push(.{ .double = stack_frame.local_variables.items[i].double }),
                            .dload_0 => try stack_frame.operand_stack.push(.{ .double = stack_frame.local_variables.items[0].double }),
                            .dload_1 => try stack_frame.operand_stack.push(.{ .double = stack_frame.local_variables.items[1].double }),
                            .dload_2 => try stack_frame.operand_stack.push(.{ .double = stack_frame.local_variables.items[2].double }),
                            .dload_3 => try stack_frame.operand_stack.push(.{ .double = stack_frame.local_variables.items[3].double }),

                            .iconst_m1 => try stack_frame.operand_stack.push(.{ .int = -1 }),
                            .iconst_0 => try stack_frame.operand_stack.push(.{ .int = 0 }),
                            .iconst_1 => try stack_frame.operand_stack.push(.{ .int = 1 }),
                            .iconst_2 => try stack_frame.operand_stack.push(.{ .int = 2 }),
                            .iconst_3 => try stack_frame.operand_stack.push(.{ .int = 3 }),
                            .iconst_4 => try stack_frame.operand_stack.push(.{ .int = 4 }),
                            .iconst_5 => try stack_frame.operand_stack.push(.{ .int = 5 }),

                            .fconst_0 => try stack_frame.operand_stack.push(.{ .float = 0 }),
                            .fconst_1 => try stack_frame.operand_stack.push(.{ .float = 1 }),
                            .fconst_2 => try stack_frame.operand_stack.push(.{ .float = 2 }),

                            .dconst_0 => try stack_frame.operand_stack.push(.{ .double = 0 }),
                            .dconst_1 => try stack_frame.operand_stack.push(.{ .double = 1 }),

                            .iadd => try stack_frame.operand_stack.push(.{ .int = stack_frame.operand_stack.pop().int + stack_frame.operand_stack.pop().int }),
                            .imul => try stack_frame.operand_stack.push(.{ .int = stack_frame.operand_stack.pop().int * stack_frame.operand_stack.pop().int }),
                            .isub => {
                                var stackvals = stack_frame.operand_stack.popToStruct(struct { a: primitives.int, b: primitives.int });
                                try stack_frame.operand_stack.push(.{ .int = stackvals.a - stackvals.b });
                            },
                            .idiv => {
                                var stackvals = stack_frame.operand_stack.popToStruct(struct { numerator: primitives.int, denominator: primitives.int });
                                try stack_frame.operand_stack.push(.{ .int = @divTrunc(stackvals.numerator, stackvals.denominator) });
                            },

                            .fadd => try stack_frame.operand_stack.push(.{ .float = stack_frame.operand_stack.pop().float + stack_frame.operand_stack.pop().float }),
                            .fmul => try stack_frame.operand_stack.push(.{ .float = stack_frame.operand_stack.pop().float * stack_frame.operand_stack.pop().float }),
                            .fsub => {
                                var stackvals = stack_frame.operand_stack.popToStruct(struct { a: primitives.float, b: primitives.float });
                                try stack_frame.operand_stack.push(.{ .float = stackvals.a - stackvals.b });
                            },
                            .fdiv => {
                                var stackvals = stack_frame.operand_stack.popToStruct(struct { numerator: primitives.float, denominator: primitives.float });
                                try stack_frame.operand_stack.push(.{ .float = stackvals.numerator / stackvals.denominator });
                            },

                            .dadd => try stack_frame.operand_stack.push(.{ .double = stack_frame.operand_stack.pop().double + stack_frame.operand_stack.pop().double }),
                            .dmul => try stack_frame.operand_stack.push(.{ .double = stack_frame.operand_stack.pop().double * stack_frame.operand_stack.pop().double }),
                            .dsub => {
                                var stackvals = stack_frame.operand_stack.popToStruct(struct { a: primitives.double, b: primitives.double });
                                try stack_frame.operand_stack.push(.{ .double = stackvals.a - stackvals.b });
                            },
                            .ddiv => {
                                var stackvals = stack_frame.operand_stack.popToStruct(struct { numerator: primitives.double, denominator: primitives.double });
                                try stack_frame.operand_stack.push(.{ .double = stackvals.numerator / stackvals.denominator });
                            },

                            // Conditionals / jumps
                            // TODO: Implement all conditions (int comparison, 0 comparison, etc.)
                            .goto => |offset| {
                                try fbs.seekBy(offset - @intCast(i16, opcode.sizeOf()));
                            },

                            .if_icmple => |offset| {
                                var stackvals = stack_frame.operand_stack.popToStruct(struct { value1: primitives.int, value2: primitives.int });
                                if (stackvals.value1 <= stackvals.value2) {
                                    try fbs.seekBy(offset - @intCast(i16, opcode.sizeOf()));
                                }
                            },
                            .if_icmpge => |offset| {
                                var stackvals = stack_frame.operand_stack.popToStruct(struct { value1: primitives.int, value2: primitives.int });
                                if (stackvals.value1 >= stackvals.value2) {
                                    try fbs.seekBy(offset - @intCast(i16, opcode.sizeOf()));
                                }
                            },
                            .if_icmpne => |offset| {
                                var stackvals = stack_frame.operand_stack.popToStruct(struct { value1: primitives.int, value2: primitives.int });
                                if (stackvals.value1 != stackvals.value2) {
                                    try fbs.seekBy(offset - @intCast(i16, opcode.sizeOf()));
                                }
                            },

                            .ifeq => |offset| {
                                var value = stack_frame.operand_stack.pop().int;
                                if (value == 0) {
                                    try fbs.seekBy(offset - @intCast(i16, opcode.sizeOf()));
                                }
                            },
                            .ifne => |offset| {
                                var value = stack_frame.operand_stack.pop().int;
                                if (value != 0) {
                                    try fbs.seekBy(offset - @intCast(i16, opcode.sizeOf()));
                                }
                            },
                            .iflt => |offset| {
                                var value = stack_frame.operand_stack.pop().int;
                                if (value < 0) {
                                    try fbs.seekBy(offset - @intCast(i16, opcode.sizeOf()));
                                }
                            },
                            .ifle => |offset| {
                                var value = stack_frame.operand_stack.pop().int;
                                if (value <= 0) {
                                    try fbs.seekBy(offset - @intCast(i16, opcode.sizeOf()));
                                }
                            },

                            .fcmpg, .fcmpl => {
                                var stackvals = stack_frame.operand_stack.popToStruct(struct { value1: primitives.float, value2: primitives.float });
                                try stack_frame.operand_stack.push(.{ .int = if (stackvals.value1 > stackvals.value2) @as(primitives.int, 1) else if (stackvals.value1 == stackvals.value2) @as(primitives.int, 0) else @as(primitives.int, -1) });
                            },

                            // Casts
                            .i2b => try stack_frame.operand_stack.push(.{ .byte = @intCast(primitives.byte, stack_frame.operand_stack.pop().int) }),
                            .i2c => try stack_frame.operand_stack.push(.{ .char = @intCast(primitives.char, stack_frame.operand_stack.pop().int) }),
                            .i2d => try stack_frame.operand_stack.push(.{ .double = @intToFloat(primitives.double, stack_frame.operand_stack.pop().int) }),
                            .i2f => try stack_frame.operand_stack.push(.{ .float = @intToFloat(primitives.float, stack_frame.operand_stack.pop().int) }),
                            .i2l => try stack_frame.operand_stack.push(.{ .long = @intCast(primitives.long, stack_frame.operand_stack.pop().int) }),
                            .i2s => try stack_frame.operand_stack.push(.{ .short = @intCast(primitives.short, stack_frame.operand_stack.pop().int) }),

                            .f2i => try stack_frame.operand_stack.push(.{ .int = @floatToInt(primitives.int, stack_frame.operand_stack.pop().float) }),

                            // Invoke thangs
                            .invokestatic => |index| {
                                var methodref = stack_frame.class_file.resolveConstant(index).methodref;
                                var nti = methodref.getNameAndTypeInfo(class_file.constant_pool);
                                var class_info = methodref.getClassInfo(class_file.constant_pool);

                                var name = nti.getName(class_file.constant_pool);
                                var class_name_slashes = class_info.getName(class_file.constant_pool);
                                var class_name = try classToDots(self.allocator, class_name_slashes);
                                defer self.allocator.free(class_name);

                                var descriptor_str = nti.getDescriptor(class_file.constant_pool);
                                var method_desc = try descriptors.parseString(self.allocator, descriptor_str);

                                var params = try self.allocator.alloc(primitives.PrimitiveValue, method_desc.method.parameters.len);
                                for (method_desc.method.parameters) |param, i| {
                                    params[i] = switch (param.*) {
                                        .byte => .{ .byte = stack_frame.operand_stack.pop().byte },
                                        .char => .{ .char = stack_frame.operand_stack.pop().char },

                                        .int, .boolean => .{ .int = stack_frame.operand_stack.pop().int },
                                        .long => .{ .long = stack_frame.operand_stack.pop().long },
                                        .short => .{ .short = stack_frame.operand_stack.pop().short },

                                        .float => .{ .float = stack_frame.operand_stack.pop().float },
                                        .double => .{ .double = stack_frame.operand_stack.pop().double },

                                        .object, .array, .method => unreachable,

                                        else => unreachable,
                                    };
                                }
                                std.mem.reverse(primitives.PrimitiveValue, params);

                                try stack_frame.operand_stack.push(try self.interpret(try self.class_resolver.resolve(class_name), name, params));

                                std.log.info("return to method: {s}", .{descriptor_buf.items});
                            },

                            // Return
                            .ireturn, .freturn, .dreturn => return stack_frame.operand_stack.pop(),
                            .@"return" => return .@"void",

                            else => {},
                        }
                        opcode = opcodes.Operation.readFrom(fbs_reader) catch break;
                    }
                },
                .unknown => {},
            }
        }
    }

    return .@"void";
}
