nasm -f win64 itc_collatz_reg.asm -o itc_collatz_reg.obj
rem We ensure the .itc section is executable and readable.
link /SUBSYSTEM:console /SECTION:.itc,ER itc_collatz_reg.obj msvcrt.lib legacy_stdio_definitions.lib
