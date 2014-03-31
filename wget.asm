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
push ebp
mov ebp, esp
push ebx
push esi
push edi
xor ebx, ebx
mov ebx, [ebp+16] 	;Load address of argument (URL)
cmp ebx, 0
jz exit
call GetURL   ; Accept DNS from Command Line, parse validity, move to url
call DNSLookup	;  DNS Lookup to find IP, IP is .sin_addr in server
call CreateSocket 	;  Create Socket
call MakeConnection 	;  Establish Connection 
call OpenFile	;  Open File named by last section of url
call WriteFile  
call CloseFile 

exit:
pop edi
pop esi
pop ebx
mov esp, ebp
pop ebp
mov eax, 1
int 0x80

GetURL:
	mov esi, 0   		;outer loop counter
	mov edi, 0		;inner loop counter
	.loop:
	mov al, [ebx+esi]	;load URL character
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
	ret

DNSLookup:		;2)  DNS Lookup to find IP, IP is .sin_addr in server
	mov eax, url  
	push eax
	call resolv	;nslookup url
	add esp, 4
	mov [server+sockaddr_in.sin_addr], eax
	ret


CreateSocket:           ;3)  Create Socket
	push eax	;put write file fd at top of stack 
	push dword 0
	push dword 1	;SOCK_STREAM
	push dword 2	;AF_INET
	mov ecx, esp	;ecx must point at top of stack for sys_socket
	mov ebx, 1	;sys_socket
	mov eax, 0x66	;sys_socketcall
	int 0x80   	;eax holds socket file descripter
	add esp, 16	;resets stack leaving output file fd at top
;	push eax     	;socket fd con
	ret

MakeConnection:            ;4)  Establish Connection 
	mov ecx, server
	mov ebx, 3
	mov eax, 0x66
	ret	

OpenFile:               ;5)  Open File named by last section of url
	mov eax, 5  	;open sys call number
	mov ebx, filename
	mov ecx, 0o100  ;O_CREAT creates the file
	mov edx, 0o666  ;Read and Write for user, group, and others
	int 0x80   	;opens file and eax contains file descripter
	test:
	ret

WriteFile:
	mov esi, eax
	mov edx, writingtofilelen	;Number of bytes to write
	mov ecx, writingtofile
	mov ebx, 1	;Writing to stdout
	mov eax, 4	;sys_write systemcall number
	int 0x80
	mov ebx, esi
	mov eax, 4
	int 0x80
	ret

CloseFile:
	mov eax, 6      ;sys_close systemcall number ebx must be holding fd
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
writingtofile: db 'Writing to File',0xa
writingtofilelen: equ $-writingtofile

section .bss
url resb 200
filename resb 200
