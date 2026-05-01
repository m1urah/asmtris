global write_to_screen
default rel


section .text

; Writes the given str to the screen at (X,Y), where (0,0) is the top-left
; corner. We'll use the `\x1b[Y;XH` cursor control sequence to position it.
; Errors out when X and/or Y > 999 or < 0
; Arguments:
;   rdi - Pointer to the str buffer
;   rsi - Length of the str
;   rdx - X as an integer
;   r10 - Y as an integer
; Return:
;   rax - Success (0) or error (1)
write_to_screen:
    ; Terminal dimensions don't realistically exceed (999, 999)
    cmp rdx, 999
    ja .error
    cmp r10, 999
    ja .error

    cmp rdx, 0
    jb .error
    cmp r10, 0
    jb .error

    ; === PROLOGUE ===
    ; Stack frame for the function
    push rbp
    mov rbp, rsp
    sub rsp, 11                 ; X (3B) + Y (3B) + `\x1b`, `[`, `;`, `H` + \0

    push rsi                    ; Save original string length
    push rdi                    ; Save original string pointer

    mov byte [rbp-11], `\x1b`
    mov byte [rbp-10], `[`

    mov rdi, r10                ; Y coordinate
    lea rsi, [rbp-9]
    call _itoa

    mov r10, rax                ; Y str len
    mov byte [rbp-9+r10], `;`

    mov rdi, rdx                ; X coordinate
    lea rsi, [rbp-8+r10]        ; 8 accounts for the `;`
    call _itoa

    add r10, rax                ; Y + X str len
    mov byte [rbp-8+r10], `H`

    ; Print the ANSI escape string to position cursor
    lea rdi, [rbp-11]
    lea rsi, [r10+5]
    xor rdx, rdx
    call _write_to_stdout

    ; Print the actual string
    pop rdi
    pop rsi
    xor rdx, rdx
    call _write_to_stdout

    ; Restore stack
    mov rsp, rbp
    pop rbp

    mov rax, 0
    ret

    .error:
        mov rax, 1
        ret


; =======  Helpers  ======================================================== #

; Converts an integer into its ASCII representation
; Arguments:
;   rdi - Integer
;   rsi - Pointer to the caller-allocated buffer
; Return:
;   rax - Length of the generated string
_itoa:
    mov rax, rdi
    mov rbx, 10
    xor r8, r8          ; str ptr
    xor r9, r9          ; Pushed digits

    .get_digits:
        xor rdx, rdx
        div rbx

        push rdx
        inc r9

        test rax, rax
        jnz .get_digits

    mov rax, r9         ; str len (ret value)

    .digit_to_ascii:
        pop rbx         ; Retrieves digits in correct order
        dec r9

        lea rcx,  [rbx + '0']
        mov byte [rsi + r8], cl
        inc r8

        test r9, r9
        jnz .digit_to_ascii

    mov byte [rsi + r8], 0x0
    ret

; Writes the given str to stdout with a new line
; Arguments:
;   rdi - Pointer to the str buffer
;   rsi - Length
;   rdx - Wether to print newline (1) or not (0)
; Return:
;   rax - Success (0) or error (1)
_write_to_stdout:
    mov r8, rdi
    mov r9, rsi
    xor r10, r10

    test rdx, rdx
    jz .write_it

    cmp rdx, 1
    je .write_it

    mov rax, 1          ; Error
    jmp .return

    .write_it:
        mov rdi, 1
        mov rsi, r8
        mov rdx, r9
        mov rax, 1
        syscall

        test r10, r10
        jz .return

        dec rsp
        mov byte [rsp], `\n`

        mov rdi, 1
        mov rsi, rsp
        mov rdx, 1
        mov rax, 1
        syscall

        inc rsp
        mov rax, 0      ; Success

    .return:
        ret