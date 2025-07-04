;;; This is similar to dtc_collatz_reg.asm but instead
;;; we use direct threading. We no longer need the work
;;; pointer.

;;; For the DTC implementation we have:
; R12: IP               ; the next word to execute
; R13: data SP          ; Except TOS
; R14: return SP
; RBX: TOS (top of stack)

global main
extern printf, fprintf, malloc, strtoll

section .data
txt_usage db "Usage: %s <initial_integer>", 10, 0
txt_bad_number db "Bad number or <=0 provided", 10, 0
txt_start db "Collatz sequence starting with %lld", 10, 10, 0
txt_collatz_num db "Step (%6lld): %16lld", 10, 0

%macro dtc_next 0
    mov rax, [r12] ; W = *IP
    add r12, 8 ; ++IP
    jmp rax  ; JMP to W
%endmacro

%define NEST jmp near dtc_nest

; Macro to ensure first address of code word points to machine instructions.
; With DTC this is no longer needed.
%macro code_word 0
;    jmp ._pfa
;._pfa:
%endmacro

section .text
;int main(int argc, char* argv[])
main:
    push r12
    push r13
    push r14
    push rbx
    sub rsp, 40

    ; Require single argument
    cmp ecx, 2
    jne .usage
    ; Parse argument
    mov rcx, [rdx+8] ; argv[1]
    mov edx, 0
    mov r8d, 10
    call strtoll
    test rax, rax
    jle .bad_number
    mov qword [rsp+32], rax

.interpreter:
    ; Write starting message
    mov r9d, eax
    lea rcx, [rel txt_start]
    mov rdx, rax
    xor rax, rax
    call printf
    xor rax, rax

    ; Create data stack
    mov rcx, 4096
    call malloc
    test rax, rax
    jz .fail
    mov r13, rax
    add r13, 4096 

    ; Create return stack
    mov rcx, 4096
    call malloc
    test rax, rax
    jz .fail
    mov r14, rax
    add r14, 4096

    ; Put initial command argument onto data stack
    mov rbx, qword [rsp+32]
    
    ; Setup return address target on return stack
    sub r14, 8
    lea rax, [rel .exit]
    mov [r14], rax

    ; Load IP to our entry code and start the inner interpretation
    lea r12, [rel code_entry]
    dtc_next

    ; We should not reach here.
    jmp .exit
.bad_number:
    lea rcx, [rel txt_bad_number]
    call printf
    jmp .fail
.usage:
    ; rcx, rdx preserved still.
    mov rdx, [rdx+0] ; argv[0]
    lea rcx, [rel txt_usage]
    call printf
    jmp .fail ; Could fall through instead...
.fail:
    mov rax, 1
    jmp .epilog ; Could fall through instead...
.exit:
    mov rax, 0
    jmp .epilog ; Could fall through instead...
.epilog:
    add rsp, 40
    pop rbx
    pop r14
    pop r13
    pop r12
    ret

; We use custom section name in hope of preventing
; link.exe from "optimizing away" these instructions
section .dtc

;;; Core control words

align 16
dtc_nest:
    ; PUSH IP onto return stack
    sub r14, 8
    mov [r14], r12
    ; Set IP to after the JMP
    ;; We can recover it like this
    ;;; mov rax, [r12 - 8] ; RAX points to our CFA the JMP to here.
    ;;; lea r12, [rax + 5] ; +5 to skip the JMP to here.
    ; But we still have it in RAX.
    lea r12, [rax + 5]
    dtc_next

align 16
dtc_unnest: code_word
    mov r12, [r14] ; POP IP from stack
    add r14, 8
    dtc_next

align 16
dtc_exit: code_word
    mov r12, [r14]
    add r14, 8
    jmp r12

align 16
branch: code_word
    mov rax, [r12]
    add r12, rax
    dtc_next

align 16
; ( b -- )  also known as 0branch
zero_branch: code_word
    mov rax, rbx
    mov rbx, [r13]
    add r13, 8
    test rax, rax
    jnz .skip
    mov rax, [r12]
    add r12, rax
    dtc_next
.skip:
    add r12, 8
    dtc_next

;;; Word manipulation

; ( x -- x x)
dup: code_word
    sub r13, 8
    mov [r13], rbx
    dtc_next
; ( x y -- y x)
swap: code_word
    mov rax, rbx
    mov rbx, [r13]
    mov [r13], rax
    dtc_next
; ( x y -- x y x)
over: code_word
    sub r13, 8
    mov [r13], rbx
    mov rbx, [r13+8]
    dtc_next

; ( x -- )
drop: code_word
    mov rbx, [r13]
    add r13, 8
    dtc_next

; ( -- x)
push_word: code_word
    sub r13, 8
    mov [r13], rbx
    mov rbx, [r12]
    add r12, 8
    dtc_next

; ( x y -- x==y )
op_equal: code_word
    mov rax, [r13]
    add r13, 8
    cmp rax, rbx
    sete al
    neg al
    sbb rax, rax
    mov rbx, rax
    dtc_next

;;; Math / comparisons

; ( a b -- a+b)
int_add: code_word
    mov rax, [r13]
    add r13, 8
    add rbx, rax
    dtc_next 
; ( a b -- a-b)
int_sub: code_word
    mov rax, rbx
    mov rbx, [r13]
    add r13, 8
    sub rbx, rax
    dtc_next 
; ( a, b -- a*b)
int_mul: code_word
    mov rax, [r13]
    add r13, 8
    imul rbx, rax
    dtc_next


; ( n -- b )
int_is_even: code_word
    and rbx, 0x01
    xor rbx, 1
    dtc_next

; ( a b -- a/b )
int_divide: code_word
    mov rax, [r13]
    add r13, 8
    xor rdx, rdx
    idiv rbx
    mov rbx, rax
    dtc_next

; I/O

; ( x y format-str -- )
print_two_args: code_word
    mov rcx, rbx
    mov rdx, [r13+8]
    mov r8, [r13]
    call printf
    mov rbx, [r13+16]
    add r13, 24
    dtc_next

; ( x format-str -- )
print_single_arg: code_word
    mov rcx, rbx
    mov rdx, [r13]
    call printf
    mov rbx, [r13+8]
    add r13, 16
    dtc_next

;;; Collatz

align 16
int_inc:
    NEST
    dq push_word
    dq 1
    dq int_add
    dq dtc_unnest

align 16
collatz: ; ( n -- )
    NEST
    dq push_word
    dq 0
    dq swap
.start:
    ; Print current number and steps
    dq over ; We could also
    dq over ; implement 2dup
    dq push_word
    dq txt_collatz_num
    dq print_two_args
    ; Check if 1 and done.
    dq dup
    dq push_word
    dq 1
    dq op_equal
    dq zero_branch
    dq .step - $
.end:
    dq drop
    dq drop
    dq dtc_unnest
.step:
    dq dup
    dq int_is_even
    dq zero_branch
    dq .not_even - $
; Number is even
    dq push_word
    dq 2
    dq int_divide
    dq branch
    dq .again - $
.not_even:
    dq push_word
    dq 3
    dq int_mul
    dq push_word
    dq 1
    dq int_add
.again:
    ; Increment step counter
    dq swap
    dq int_inc
    dq swap
    dq branch
    dq .start - $
code_entry:
    dq collatz
    dq dtc_exit
