nasm -f win64 find_ip.asm -o find_ip.obj
link find_ip.obj /subsystem:console kernel32.lib shell32.lib user32.lib Ws2_32.lib /entry:main
