nasm -f win64 itc_collatz.asm -o itc_collatz.obj
rem We ensure the .itc section is executable and readable.
link /SUBSYSTEM:console /SECTION:.itc,ER itc_collatz.obj msvcrt.lib legacy_stdio_definitions.lib
