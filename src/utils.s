global write_to_screen, strlen
default rel


section .text

; Writes the given str to the screen at (X,Y), where (1,1) is the top-left
; corner. We'll use the `\x1b[Y;XH` cursor control sequence to position it.
; Errors out when X and/or Y > 999 or < 1
; Arguments:
;   rdi - Pointer to the str buffer
;   rsi - Length of the str
;   rdx - X as an integer
;   r10 - Y as an integer
; Return:
;   rax - Number of bytes written
write_to_screen:
    ; Terminal dimensions don't realistically exceed (999, 999)
    cmp rdx, 999
    ja .error
    cmp r10, 999
    ja .error

    cmp rdx, 1
    jb .error
    cmp r10, 1
    jb .error

    ; === PROLOGUE ===
    ; Stack frame for the function
    push rbp
    mov rbp, rsp
    sub rsp, 10                 ; X (3B) + Y (3B) + `\x1b`, `[`, `;`, `H`

    ; Save originals for later
    push rsi
    push rdi 
    push rdx

    mov byte [rbp-10], `\x1b`
    mov byte [rbp-9], `[`

    mov rdi, r10                ; Y coordinate
    lea rsi, [rbp-8]
    call _itoa

    mov r10, rax                ; Y str len
    mov byte [rbp-8+r10], `;`

    pop rdi                     ; X coordinate (rdx in stack)
    lea rsi, [rbp-7+r10]        ; 8 accounts for the `;`
    call _itoa

    add r10, rax                ; Y + X str len
    mov byte [rbp-7+r10], `H`

    ; Print the ANSI escape string to position cursor
    mov rax, 1
    mov rdi, 1
    lea rsi, [rbp-10]
    lea rdx, [r10+4]
    syscall

    cmp rax, rdx                ; null terminator is not written
    jne .error

    ; Print the actual string
    mov rax, 1
    mov rdi, 1
    pop rsi
    pop rdx
    syscall

    ; Restore stack
    mov rsp, rbp
    pop rbp

    ret

    .error:
        mov rax, 0
        ret

; Returns the byte-length of a given string up-to 1024 bytes. If the string has
; multi-byte UTF-8 characters, each byte is counted individually.
; Arguments:
;   rdi - Pointer to the null-terminated string buffer
;   rsi - Maximum number of characters to examine
; Return:
;   rax - Byte-length of the string (excluding null terminator), or zero if str
;         is a null pointer, and rsi if the null character was not found in the
;         first rsi bytes.
strlen:
    xor eax, eax            ; al = 0
    test rdi, rdi
    jz .done

    cld                     ; Ensure we are scanning FORWARD
    mov rcx, rsi

    repne scasb             ; Scan while [rdi] != al AND rcx != 0

    xor rdi, rdi
    setz dil                ; Save og ZF flag

    mov rax, rsi
    sub rax, rcx            ; rax = bytes_scanned
    
    test dil, dil
    jz .done                ; ZF=0 -> no null found, we hit limit -> rax == rsi
    dec rax                 ; ZF=1 -> found null -> exclude null from length

    .done:
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
