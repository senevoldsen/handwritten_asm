;;; Demonstration of ITC (indirect threaded code)
;;; The core inner interpreter in macro itc_next
;;;
;;; Here we just use it to print the collatz sequence
;;;
;;; The CFA of each word is thus an address to machine code
;;; For code words it points to the first instruction which is
;;; at the address location right after.
;;;
;;; For colon words it usually points to itc_nest which pushes
;;; the current IP onto the stack so we can resume later.
;;;
;;; Minor detail: since code words may call functions we have
;;;   ensured that that RSP is 16-byte aligned before runining
;;    our inner interpreter.
;;;
;;; READERS: who somehow found themselves here, and want to
;;;   look further, take a look at: https://muforth.dev/threaded-code/

;;; For the ITC implementation we have:
; R12: IP               ; the next word to execute
; R13: data SP
; R14: return SP
; R15: work pointer     ; the currently executing word

global main
extern printf, fprintf, malloc, strtoll

section .data
txt_usage db "Usage: %s <initial_integer>", 10, 0
txt_bad_number db "Bad number or <=0 provided", 10, 0
txt_start db "Collatz sequence starting with %lld", 10, 10, 0
txt_collatz_num db "Step (%6lld): %16lld", 10, 0

%macro itc_next 0
    mov r15, [r12] ; W = *IP
    add r12, 8 ; ++IP
    jmp [r15]  ; JMP to W
%endmacro

; Macro to ensure first address of code word points to machine instructions.
%macro code_word 0
    dq ._pfa
._pfa:
%endmacro

section .text
;int main(int argc, char* argv[])
main:
    push r12
    push r13
    push r14
    push r15
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
    mov rax, qword [rsp+32]
    sub r13, 8
    mov [r13], rax ; SP = [ INIT_INT ]

    ; Setup return address target on return stack
    sub r14, 8
    lea rax, [rel .exit]
    mov [r14], rax

    ; Load IP to our entry code and start the inner interpretation
    lea r12, [rel code_entry]
    itc_next

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
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; We use custom section name in hope of preventing
; link.exe from "optimizing away" these instructions
section .itc

;;; Core control words

align 16
itc_nest:
    ; PUSH IP onto return stack
    sub r14, 8
    mov [r14], r12
    ; Set IP to W + address_size
    lea r12, [r15 + 8]
    itc_next

align 16
itc_unnest: code_word
    mov r12, [r14] ; POP IP from stack
    add r14, 8
    itc_next

align 16
itc_exit: code_word
    mov r12, [r14]
    add r14, 8
    jmp r12

align 16
branch: code_word
    mov rax, [r12]
    add r12, rax
    itc_next

align 16
; ( b -- )  also known as 0branch
zero_branch: code_word
    mov rax, [r13]
    add r13, 8
    test rax, rax
    jnz .skip
    mov rax, [r12]
    add r12, rax
    itc_next
.skip:
    add r12, 8
    itc_next

;;; Word manipulation

; ( x -- x x)
dup: code_word
    mov rax, [r13]
    sub r13, 8
    mov [r13], rax
    itc_next
; ( x y -- y x)
swap: code_word
    mov rax, [r13]
    mov rcx, [r13+8]
    mov [r13], rcx
    mov [r13+8], rax
    itc_next
; ( x y -- x y x)
over: code_word
    sub r13, 8
    mov rax, [r13+16]
    mov [r13], rax
    itc_next

; ( x -- )
drop: code_word
    add r13, 8
    itc_next

; ( -- x)
push_word: code_word
    mov rax, [r12]
    add r12, 8
    sub r13, 8
    mov [r13], rax
    itc_next

; ( x y -- x==y )
op_equal: code_word
    mov rax, [r13+8]
    mov rcx, [r13]
    add r13, 8
    cmp rax, rcx
    sete al
    neg al
    sbb rax, rax
    mov [r13], rax
    itc_next

;;; Math / comparisons

; ( a b -- a+b)
int_add: code_word
    mov rax, [r13]
    add r13, 8
    add [r13], rax
    itc_next 
; ( a b -- a-b)
int_sub: code_word
    mov rax, [r13]
    add r13, 8
    sub [r13], rax
    itc_next 
; ( a, b -- a*b)
int_mul: code_word
    mov rax, [r13+8]
    imul rax, [r13]
    add r13, 8
    mov [r13], rax
    itc_next


; ( n -- b )
int_is_even: code_word
    mov rax, [r13]
    and rax, 0x01
    xor rax, 1
    mov [r13], rax
    itc_next

; ( a b -- a/b )
int_divide: code_word
    mov rdx, 0
    mov rax, [r13+8]
    mov rcx, [r13]
    div rcx
    add r13, 8
    mov [r13], rax
    itc_next

; I/O

; ( x y format-str -- )
print_two_args: code_word
    mov rcx, [r13]
    mov rdx, [r13+16]
    mov r8, [r13+8]
    add r13, 24
    call printf
    itc_next

; ( x format-str -- )
print_single_arg: code_word
    mov rcx, [r13]
    mov rdx, [r13+8]
    add r13, 16
    call printf
    itc_next

;;; Collatz

align 16
int_inc:
    dq itc_nest
    dq push_word
    dq 1
    dq int_add
    dq itc_unnest

align 16
collatz: ; ( n -- )
    dq itc_nest
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
    dq itc_unnest
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
    dq itc_exit
