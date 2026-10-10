fn syscall1(number: usize, arg1: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
        : .{ .rcx = true, .r11 = true, .memory = true });
}

fn nop() void {
    asm volatile ("nop");
    asm volatile ("" ::: .{ .memory = true });
    var x: u32 = 0;
    asm ("mov %[a], %[out]"
        : [out] "=r" (x),
        : [a] "r" (1),
    );
}
