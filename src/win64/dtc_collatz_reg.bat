nasm -f win64 dtc_collatz_reg.asm -o dtc_collatz_reg.obj
rem We ensure the .dtc section is executable and readable.
link /SUBSYSTEM:console /SECTION:.dtc,ER dtc_collatz_reg.obj msvcrt.lib legacy_stdio_definitions.lib
