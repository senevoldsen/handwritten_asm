%define STDOUT_HANDLE -11

section .data

hStdOut     dq 0
pCmdArgs    dq 0
iNumArgs    dw 0
; Is apparently 408 bytes...
pWsaData    db 408 dup(0)

protDNS     dd 12
protService dw __utf16__('80'), 0
errorTitle  dw __utf16__('Error'), 0
errorText   dw __utf16__('Error Code: '), 0
errorBadLookup dw __utf16__('Error looking up'), 0

section .text
global main
extern GetStdHandle, WriteFile, ExitProcess
extern GetCommandLineW, CommandLineToArgvW
extern lstrlenW
extern GetLastError, MessageBoxW
extern GetAddrInfoExW, WSAStartup, WSACleanup, FreeAddrInfoExW


main:
    ; Setup stack: align + shadow space
    sub rsp, 40

    ; Get Handle
    mov ecx, STDOUT_HANDLE
    call GetStdHandle
    mov [rel hStdOut], rax
    cmp rax, -1
    je error_exit

    ; Init WSA
    mov rcx, 0x0202
    lea rdx, [rel pWsaData]
    call WSAStartup
    cmp rax, 0
    jne error_exit

    ; Call with function pointer
    call get_args
    lea rcx, [rel lookup_args]
    call with_cmd_args

    call WSACleanup

    xor rcx, rcx
    call ExitProcess
error_exit:
    sub rsp, 32
    call GetLastError
    mov rcx, rax
    lea rdx, [rsp+32] ; Use the previously main shadow space
    call int_to_wstr
    mov rcx, 0
    ;; lea rdx, [rel errorText]
    lea rdx, [rsp+32]
    lea r8, [rel errorTitle]
    mov r9, 0
    call MessageBoxW
    xor ecx, ecx
    call ExitProcess


; print_wstr(lpWstr)
print_wstr:
    sub rsp, 40
    mov [rsp+32], rcx
    call lstrlenW
    shl eax, 1
    mov rcx, [rel hStdOut]
    mov rdx, [rsp+32]
    mov r8, rax
    mov r9, 0
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 40
    ret
get_args:
    sub rsp, 40
    call GetCommandLineW
    mov rcx, rax
    ; RDX passes pointer to count.
    lea rdx, [rsp + 32]
    call CommandLineToArgvW
    test rax, rax
    jz error_exit
    mov [rel pCmdArgs], rax
    mov rax, [rsp + 32]
    mov [rel iNumArgs], rax
    add rsp, 40
    ret


; print_arguments(int64 i, wstr* arg)
print_arguments:
    sub rsp, 56
    ; Win64 prolog rules "forbids" popping in middle
    ; so manually allocate extra stack space.
    mov [rsp+32], rdx
    cmp rcx, 0
    jle .return ; no program name itself
    cmp rcx, 1
    jle .arg
    ; Preface non-first args with
    ; space and wide null
    mov dword [rsp+40], 0x00000020
    lea rcx, [rsp+40]
    call print_wstr
    mov rdx, [rsp+32]
.arg:
    mov rcx, rdx
    call print_wstr
.return:
    add rsp, 56
    ret


; Naive integer to wide string.
; Buffer must be 2-byte aligned.
; You may pass an unsigned as long as it fit in int.
; int_to_wstr(int num, wstr* buffer)
int_to_wstr:
    push rdi
    push rsi
    mov rdi, rdx
    mov rsi, rdx
    add rsi, 24 ; backwards pointer
    mov r10, 0 ; digit counter
    test ecx, ecx
    jge .divide
    mov word [rdi], 0x002D ; -
    add rdi, 2
    neg ecx
.divide:
    sub rsi, 2
    inc r10
    mov edx, 0
    mov eax, ecx
    mov r9d, 10
    div r9d
    mov ecx, eax
    add edx, 0x30 ; to digit
    mov word [rsi], dx
    test ecx, ecx
    jnz .divide
    ; Shift to left-align
    ; rdi is where to place
    ; rsi left most char
    mov rcx, r10
    rep movsw
    ; Add null byte
    mov word [rdi], 0x0000
    pop rsi
    pop rdi
    ret


; Formats ipv4 address in buffer
; Buffer must be 2-byte aligned and at least 32 bytes
; format_ipv4(uint32_t IP_addr, wstr* buffer):
format_ipv4:
    push r12
    push rbx
    push rdi ; Write pointer
    push rsi
    sub rsp, 40

    mov ebx, ecx ; ip
    mov rdi, rdx ; Write pointer
    
    mov r12, 0
.octet:
    ; Mask off byte
    imul ecx, r12d, 8
    mov eax, ebx
    shr eax, cl
    and eax, 0xff
    ; Format number
    mov ecx, eax
    mov rdx, rdi
    call int_to_wstr
    ; Skip until our null byte.
.find_null:
    cmp word [rdi], 0x0000
    je .done_null
    add rdi, 2
    jmp .find_null
.done_null:
    inc r12
    cmp r12, 4
    jge .return
    ; Write '.'
    mov word [rdi], 0x002E ; Period
    add rdi, 2
    jmp .octet
.return:
    mov word [rdi], 0x0000 ; end string
    add rsp, 40
    pop rsi
    pop rdi
    pop rbx
    pop r12
    ret


; lookup_args(int64 i, pWstr arg)
lookup_args:
    push r12
    push r13
    sub rsp, 88
    cmp rcx, 0
    jle .done

    mov [rsp+32], rdx
    mov rcx, rdx
    call print_wstr

    ; Print: ':\n'
    mov word [rsp+40], 0x003a
    mov word [rsp+42], 0x000a
    mov word [rsp+44], 0x0000
    lea rcx, [rsp+40]
    call print_wstr

    ; Make request
    mov rcx, [rsp+32] ; pName
    ; lea rdx, [rel protService] ; pServiceName
    xor rdx, rdx
    mov r8, [rel protDNS] ; dwNameSpace
    mov r9, 0  ; lpNspId

    mov r13, 0 ; Null ppResult register.
    mov qword [rsp+32], 0 ; *hints
    lea rax, [rsp+80]
    mov [rsp+40], rax     ; *ppResult
    mov qword [rsp+48], 0 ; *timeout
    mov qword [rsp+56], 0 ; lpOverlapped
    mov qword [rsp+64], 0 ; lpCompletionRoutine
    mov qword [rsp+72], 0 ; lpHandle
    call GetAddrInfoExW
    test eax, eax
    jnz .bad_entry
    mov r12, [rsp+80]
    mov r13, r12 ; Store original ppResults
    ; r12 is now pointer to linked list
.loop_entries:
    test r12, r12
    jz .clean
    ; ai_flags
    mov eax, [r12+4]
    cmp eax, 2 ; AF_INET
    jne .next_entry
    ; Write indent
    mov qword [rsp+32], 0x000000200020
    lea rcx, [rsp+32]
    call print_wstr
    ; ai_addr
    mov rcx, [r12+32]
    mov rcx, [rcx+4]
    ; we have ip4 address in rcx now.
    lea rdx, [rsp+32]
    call format_ipv4
    lea rcx, [rsp+32]
    call print_wstr
    ; We are at least 8 byte aligned so we can do it in one.
    mov dword [rsp+32], 0x0000000a ; '\n'
    lea rcx, [rsp+32]
    call print_wstr
.next_entry:
    mov r12, [r12+64] ; Verify 64 offset
    jmp .loop_entries
.clean:
    mov dword [rsp+32], 0x0000000a
    lea rcx, [rsp+32]
    call print_wstr
    mov rcx, r13
    test rcx, rcx
    jz .done
    call FreeAddrInfoExW
.done:
    add rsp, 88
    pop r13
    pop r12
    ret
.bad_entry:
    lea rcx, [rel errorBadLookup]
    call print_wstr
    mov qword [rsp+32], 0x0000000a000a
    lea rcx, [rsp+32]
    call print_wstr
    jmp .done

    
; Calls the callback with i and argv[i]
; with_cmd_args(callback(int64 i, pWstr arg))
with_cmd_args:
    ; Store callee save registers
    push rbx
    push rdi
    push rsi
    sub rsp, 32 ; We are aligned because odd no. pushes

    mov rsi, rcx ; callback pointer
    ; Prepare loop
    mov rdi, [rel iNumArgs] ; N
    xor rbx, rbx  ; i < N
.step:
    cmp rbx, rdi
    jge .done
    mov rdx, [rel pCmdArgs]
    mov rdx, [rdx + rbx*8]
    ; Prepare args
    mov rcx, rbx
    call rsi
    inc rbx
    jmp .step
.done:
    add rsp, 32
    pop rsi
    pop rdi
    pop rbx
    ret
