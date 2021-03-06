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
mov ebx, [ebp+12] 	;Load address of argument (URL)   +16 for gdb
cmp ebx, 0x0
je error
call GetURL   	;Accept DNS from Command Line, parse validity, move to url
call DNSLookup		;DNS Lookup to find IP, IP is .sin_addr in server
cmp eax, 0
jle error
call CreateSocket 	;Create Socket
cmp eax, 0
jle error
call MakeConnection 	;Establish Connection 
cmp eax, 0		;exit if succesful connection was not created
jnz error
call OpenFile		;Open File named by last section of url
call BuildGet
call WriteFile  
call CloseFile 
jmp exit

error:
	mov edx, errorlen	;Number of bytes to write
	mov ecx, errormes
	mov ebx, 1	;Writing to stdout
	mov eax, 4	;sys_write systemcall number
	int 0x80


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
		mov ecx, esi
		jmp .newsection
		.nextchar:
		mov al, [ebx+esi]
		cmp al, 0x00
		je .endofurl
		cmp al, 0x2F	;is char slash?
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
			xor edi, edi
			.buildpath:
				mov al, [ebx+ecx]
				cmp al, 0x0
				je .pathdone
				mov [path+edi], al
				inc edi
				inc ecx
				jmp .buildpath
		.pathdone:
			cmp byte [path], 0x2F
			je .pathok
			mov byte [path], 0x2F   ;insert slash
			mov byte [path+1], 0x0
		.pathok:
	ret

DNSLookup:		;2)  DNS Lookup to find IP, IP is .sin_addr in server
	mov eax, url  
	push eax
	call resolv	;nslookup url
	add esp, 4
	mov [server+sockaddr_in.sin_addr], eax
	ret


CreateSocket:           ;3)  Create Socket
	push dword 0
	push dword 1	;SOCK_STREAM
	push dword 2	;AF_INET
	mov ecx, esp	;ecx must point at top of stack for sys_socket
	mov ebx, 1	;sys_socket
	mov eax, 0x66	;sys_socketcall
	int 0x80   	;eax holds socket file descripter
	add esp, 12	;resets stack leaving output file fd at top
	mov esi, eax	;esi now holds socket fd
	ret

MakeConnection:            ;4)  Establish Connection 
	push dword [sockaddr_size]	;sockaddr size to stack
	push server		;sockaddr struc address to stack
	push esi		;socket fd to stack
	mov ecx, esp		;top of stack to ecx
	mov ebx, 3		;connect socketcall
	mov eax, 0x66		;socketcall syscall # 102d=66x
	int 0x80
	add esp, 12
	ret	

OpenFile:               ;5)  Open File named by last section of url
	mov eax, 5  	;open sys call number
	mov ebx, filename
	mov ecx, 0o102  ;O_CREAT creates the file and makes it Read/Write
	mov edx, 0o0666 ;Read and Write for user, group, and others
	int 0x80   	;opens file and eax contains file descripter
	mov edi, eax	;moves output file descriptor into edi
	ret

BuildGet:           ;get1 path get2 url get3       strlen
	push esi
	push edi
	xor edi, edi
	xor esi, esi
	xor eax, eax
	mov al, [get1+edi]
	.get1loop:
		cmp al,0
		jz .addpath
		mov [get+edi], al
		inc edi
		mov al, [get1+edi]
		jmp .get1loop
	.addpath:
		mov al, [path+esi]
		.pathloop:
			cmp al, 0
			jz .addget2
			mov [get+edi], al
			inc edi
			inc esi
			mov al, [path+esi]
			jmp .pathloop
	.addget2:
		xor esi, esi
		mov al, [get2+esi]
		.get2loop:
			cmp al, 0
			jz .addurl
			mov [get+edi], al
			inc edi
			inc esi
			mov al, [get2+esi]
			jmp .get2loop
	.addurl:
		xor esi, esi
		mov al, [url+esi]
		.urlloop:
			cmp al, 0
			jz .addget3
			mov [get+edi], al
			inc edi
			inc esi
			mov al, [url+esi]
			jmp .urlloop
	.addget3:
		xor esi, esi
		mov al, [get3+esi]
		.get3loop:
			cmp al, 0
			jz .done
			mov [get+edi], al
			inc edi
			inc esi
			mov al, [get3+esi]
			jmp .get3loop
	.done:
	mov [getlen], edi	
	pop edi
	pop esi
	ret


WriteFile:
	mov edx, [getlen]	;Number of bytes to write
	mov ecx, get
	mov ebx, 1	;Writing to stdout
	mov eax, 4	;sys_write systemcall number
	int 0x80
	
	mov ebx, esi	;Writing to socket
	mov eax, 4	;sys_write systemcall number
	int 0x80
	
	mov edx, recbuflen
	mov ecx, recbuf
	mov ebx, esi
	mov eax, 3	;Read From Socket
	int 0x80

	mov edx, recbuflen
	mov ecx, recbuf
	mov ebx, edi
	mov eax, 4
	int 0x80
	ret

CloseFile:
	mov ebx, edi 	;File Descriptor for opened File
	mov eax, 6      ;sys_close systemcall number ebx must be holding fd
	ret

strlen:          ;l_strlen(char *str)
        ;returns the length of a null terminated string
        push ebp
        mov ebp, esp
        push esi
        push ecx
        xor esi, esi
        mov ecx, [ebp+8]
        .loop:
                cmp byte [ecx+esi], 0x0
                je .done
                add esi, 1
                jmp .loop
        .done:
        mov eax, esi
        pop ecx
        pop esi
        pop ebp
        ret


section .data
server:	istruc sockaddr_in
	at sockaddr_in.sin_family, dw 2        ;AF_INET=2
	at sockaddr_in.sin_port, dw 0x5000	;Port 80 in network byte 
  	at sockaddr_in.sin_addr, dd 0x0200a8c0	;IP Address in net byte order
iend

sockaddr_size: dd 16
invalid: db 'enter a valid url',0xa
invalidlen: equ $-invalid
defaultfilename: db 'index.html',0x00
defaultfilename_len: equ $-defaultfilename
writingtofile: db 'Writing to File',0xa
writingtofilelen: equ $-writingtofile
errormes: db 'error',0xa
errorlen: equ $-errormes
get1: db 'GET ',0x0
get1len: equ $-get1
get2: db ' HTTP/1.0',0xd,0xA,'Host:  ',0x0
get2len: equ $-get2
get3: db 0xd,0xa,0xd,0xa,0x0
get3len: equ $-get3


section .bss
url resb 200
filename resb 200
path resb 200
recbuf: resb 2000
recbuflen: equ $-recbuf
get: resb 200
getlen: resd 1
