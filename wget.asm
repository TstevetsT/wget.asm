;
;compile with nasm -f elf assn4.asm
;link/load with: ld -o assn4 assn4.o dns.o
;run with ./assn4 <URL>   
BITS 32
global _start
extern resolv

struc sockaddr_in
	.sin_family: resw 1  ;offset 0, 2 byte/8bit ?????
	.sin_port: resw 1  ;offset 2, 2 byte/8bit port number 0x5000=80
	.sin_addr: resd 1  ;offset 4, 4 byte/16 bit address 
	.sin_pad: resb 8   ;offset 8, 8 byte array
endstruc

section .text

_start:
;1)  Accept DNS from Command Line, parse for validity, and move to url
call GetURL
;2)  DNS Lookup to find IP, IP is .sin_addr in server
call DNSLookup
;3)  Open File named by last section of url
call OpenFile
;4)  Create Socket
call CreateSocket


GetURL:
push ebp
mov ebp, esp
push ebx
push edi
push esi
	mov ebx, [ebp+16] 	;Load address of argument (URL)
	mov esi, 0   		;outer loop counter
	mov edi, 0		;inner loop counter
	.loop:
	mov al, [ebx+esi]	;load URL character
	.t:
	cmp al, 0x00		;Check if Null
	jz .usedefaultfilename	;If null all char have been viewed
	cmp al, 0x2F		;check if slash
	jz .slash		
	mov [url+esi], al     	;copy char into URL
	inc esi			;increment to next URL char
	jmp .loop		
	.slash:			;If a slash in encountered	
	inc esi
	mov al, [ebx+esi]
	cmp al, 0x00		;is char null?
	je .usedefaultfilename
	cmp al, 0x2F		;is char a slash?
	je .dubslash
	dec esi
	jmp .findfilename	;slash must follow url, find filename
	.dubslash:
		inc esi
		mov al, [ebx+esi]
		cmp al, 0x00	;is char null?
		je .usedefaultfilename
		cmp al, 0x2F   	;is char a slash?
		je .findfilename
		mov [url+edi], al
		inc edi
		jmp .dubslash
	.findfilename:
		jmp .newsection
		.nextchar:
		mov al, [ebx+esi]
		cmp al, 0x00
		je .endofurl
		cmp al, 0x2F
		je .newsection
		mov [filename+edi], al
		inc esi
		inc edi
		jmp .nextchar
		.newsection:
			push esi
			mov esi, 0
			.zeroloop:
				cmp esi, edi
				je .outzeroloop
				mov byte [filename+esi], 0x00
				inc esi
				jmp .zeroloop
			.outzeroloop:
			pop esi
			inc esi
			mov edi, 0
			jmp .nextchar
		.endofurl:
		cmp byte [filename], 0
		je .usedefaultfilename
		jmp .filenamedone
	.usedefaultfilename:
		mov al, 0
		push ecx
		mov ecx, defaultfilename_len
		mov edi, 0
		.defaultfilenameloop:
			mov al, [defaultfilename+edi]
			mov [filename+edi], al
			cmp edi, ecx
			je .filenamedone
			inc edi
			jmp .defaultfilenameloop
		.filenamedone:
		pop ecx
ret

;2)  DNS Lookup to find IP, IP is .sin_addr in server
DNSLookup:
	mov eax, url  
	push eax
	call resolv	;nslookup url
	add esp, 4
mov [server+sockaddr_in.sin_addr], eax
ret

;3)  Open File named by last section of url
OpenFile:
	mov eax, 5  	;open sys call number
	mov ebx, filename
	mov ecx, 700o
	int 0x80   	;opens file and eax contains file descripter
ret

;4)  Create Socket
CreateSocket:
	push eax	;put write file fd at top of stack 
	push dword 0
	push dword 1	;SOCK_STREAM
	push dword 2	;AF_INET
	mov ecx, esp	;ecx must point at top of stack for sys_socket
	mov ebx, 1	;sys_socket
	mov eax, 0x66	;sys_socketcall
	int 0x80   	;eax holds socket file descripter
	add esp, 12	;resets stack leaving output file fd at top
	push eax     	;socket fd con
ret

;5)  Establish Connection 
	mov ecx, server
	mov ebx, 3
	mov eax, 0x66
	
;	push dword [server+sockaddr_in.sin_addr] ;Loads server IP
;	push word 0x5000   	;Port 80
;	push word 2   		;???
;	mov ecx, esp		;stack pointer to ecx for sys_socket
;	push dword 16
;	push ecx
;	push eax		;loads socket file descriptor
;	mov ecx, esp
;	mov ebx, 
 

	test:
;?)  Retrieve Contents of URL
;?)  Put contents in a file
;  socket(AF_INET,SOCK_STREAM,0)
;push dword 0    ;last argument/\
;push dword 1    ;sock_stream=1
;push dword 2    ;AF_INET=2
;mov ecx, esp
;mov ebx, 1 	;sys_socket
;mov eax, 0x66	;sys_socketcall
;int 0x80  	;fd returned in eax
pop esi
pop edi
pop ebx
mov esp, ebp
pop ebp
ret

section .data
server:	istruc sockaddr_in
	at sockaddr_in.sin_family, dw 2        ;AF_INET=2
	at sockaddr_in.sin_port, dw 0x5000	;Port
  	at sockaddr_in.sin_addr, dd 0x0200a8c0	;IP Address in net byte order
iend

sockaddr_size: dd 16
invalid: db 'enter a valid url',0xa
invalidlen: equ $-invalid
defaultfilename: db 'index.html',0x00
defaultfilename_len: equ $-defaultfilename

section .bss
url resb 200
filename resb 200

