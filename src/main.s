global _start
extern setup_board
default rel

section .rodata
    ; =======  STRUCTS  ==================================================== #
    ; man 2 sigaction
    sa_struct:
        dq exit_handler     ; sa_handler
        dq 0x04000000       ; sa_flags (SA_RESTORER)
        dq exit_restorer    ; sa_restorer
        dq 0                ; sa_mask

    ; man 3 timespec
    timespec_struct:
        dq 0                ; tv_sec
        dq 16666666         ; tv_nsec (aprox 60fps)


    ; ======  STRINGS  ===================================================== #
    ; disables buffer -> show cursor
    return_seq              db `\x1b[?1049l\x1b[?25h`
    return_len              equ $-return_seq

    cursor_home             db `\x1b[H`
    cursor_home_len         equ $-cursor_home

    read_res                db "You wrote: "
    read_res_len            equ $-read_res


section .bss
    ; Ref https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/termbits.h#L30
    ; with NCSS = 32
    termios_struct_og       resb 64    ; Backup of original settings
    termios_struct_mod      resb 64    ; Settings we modify


section .text
_start:
    call init_env
    call setup_board

    sub rsp, 1      ; User input buffer
    .infinity:
        call sleep

        ; Read user input
        mov rax, 0
        mov rdi, 0
        mov rsi, rsp
        mov rdx, 1
        syscall

        mov r15, rax    
        test r15, r15
        jz .continue_loop   ; No input?

        ; Do smth with the input here...
        
        ; Write input immediately after ;)
        mov rax, 1
        mov rdi, 1
        mov rsi, read_res
        mov rdx, read_res_len
        syscall

        mov rdi, 1
        mov rsi, rsp
        mov rdx, r15
        mov rax, 1
        syscall

        .continue_loop:
            jmp .infinity

; Initializes the terminal environment:
;   - Signal handling (CTRL+C, CTRL+Z)
;   - Disable terminal buffering and echoing
; Arguments:
;   None
; Return:
;   None
init_env:
    ; sys_rt_sigaction
    mov rax, 13             
    mov rdi, 2              ; SIGINT (CTRL+C)
    lea rsi, [sa_struct]
    mov rdx, 0              ; Don't wan no oldact
    mov r10, 8
    syscall

    ; sys_rt_sigaction
    mov rax, 13             ; SIGTSTP (CTRL+Z)
    mov rdi, 20
    syscall
    
    call modify_termios

    ret

; Sleeps the amount of time specified in the timespec_struct's tv_nsec field.
; Arguments:
;   None
; Return:
;   None
sleep:
    ; sys_nanosleep
    mov rax, 35
    lea rdi, [timespec_struct]
    mov rsi, 0
    syscall

    ret

exit_handler:
    call restore_screen

    mov rdi, 0
    mov rax, 60
    syscall

exit_restorer:
    ; rt_sigreturn
    mov rax, 15
    syscall
    ret

restore_screen:
    %define TCSETS          0x5402

    ; sys_ioctl
    mov rax, 16
    mov rdi, 0
    mov rsi, TCSETS
    mov rdx, termios_struct_og
    syscall

    mov rax, 1
    mov rdi, 1
    lea rsi, [return_seq]
    mov rdx, return_len 
    syscall

    ret

; Modify the terminal behavior using the termios struct. Disables two flags:
;   - ICANON: read keypresses immediately 
;   - ECHO: do not echo received characters
; Arguments:
;   None
; Return:
;   rax - Success (0) or error (1)
modify_termios:
    %define TCGETS          0x5401
    %define TCSETS          0x5402
    %define ICANON          0x0002
    %define ECHO            0x0008
    %define VTIME_OFFSET    5
    %define VMIN_OFFSET     6

    ; Get current settings via ioctl
    mov rdi, 0
    mov rsi, TCGETS
    mov rdx, termios_struct_og
    mov rax, 16
    syscall

    ; Copy original in 8 chunks of 8 bytes each
    lea rsi, [termios_struct_og]
    lea rdi, [termios_struct_mod]
    mov rcx, 8      ; 64 bytes / 8
    rep movsq

    ; Disable flags in c_lflag
    mov eax, [termios_struct_mod + 12]  ; offset
    and eax, ~(ICANON | ECHO)           ; bitwise AND NOT
    mov [termios_struct_mod + 12], eax

    ; Set VMIN and VTIME to 0 for non-blocking polling
    mov rax, 17                         ; c_cc offset
    mov byte [termios_struct_mod + rax + VTIME_OFFSET], 0
    mov byte [termios_struct_mod + rax + VMIN_OFFSET], 0

    ; Set new settings via ioctl
    mov rdi, 0
    mov rsi, TCSETS
    mov rdx, termios_struct_mod
    mov rax, 16
    syscall

    ret
