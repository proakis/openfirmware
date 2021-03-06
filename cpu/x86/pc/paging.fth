\ See license at end of file
purpose: Set up page tables and turn on paging

\needs start-assembling  fload ${BP}/cpu/x86/asmtools.fth
\needs write-dropin      fload ${BP}/forth/lib/mkdropin.fth

fload ${BP}/cpu/x86/mmuparam.fth

hex

fload ${BP}/cpu/x86/pc/report.fth			\ Startup reports

start-assembling
protected-mode

\ RAM is on and mem-info-pa tells the memory layout
label entry
   \ Initialize virtual page table
   \ Initialize linear=physical page table (redundant page table entries)
   \ Enable paging  (note that page fault handler is not in place yet)

[ifdef] notdef
   \ clear page tables
   ax ax  xor
   /ptab /l / #  cx  mov
   pt-pa #  di  mov
   rep  ax stos
[then]

ascii 1 report
   \ create PDEs

\ Create a mapping for the firmware

   \ In the following code, we use ESI as a physical memory allocation pointer
   mem-info-pa 4 + #)  si  mov		\ Top of memory available to software
   /page 1- invert #   si  and		\ Page-align just in case

   /fw-ram #           si  sub		\ Base address of firmware area
   si                  dx  mov		\ Firmware physical address in EDX

   \ Allocate Page Directory
   /ptab #             si  sub
   si                  bx  mov		\ Page directory PA in EBX

   \ Clear Page Directory
   ax ax  xor			\ value to store
   /ptab /l / #  cx  mov	\ #words to clear
   bx  di  mov			\ Base address
   rep ax stos

   /ptab #             si  sub
   si                  bp  mov		\ Page table PA in EBP
   
   bp                  ax  mov
   pte-control #       ax  or		\ Page table PDE in EAX
   ax   fw-virt-base d# 22 rshift /l*  [bx]  mov  \ Set page directory entry

   \ Fill page table with entries for the firmware
   bp                  di  mov
   dx                  ax  mov
   pte-control #       ax  or		\ Firmware PTE in EAX
   /fw-ram /page / #   cx  mov		\ Number of entries
   begin
      ax stos				\ Set PTE
      /page #  ax  add
   loopa

   \ Clear the rest of the table
   ax ax xor				\ Invalid page
   /section /fw-ram - /page / #      cx  mov	\ Number of entries
   rep ax stos

\ Linearly-map low addresses to cover physical memory
\ This code could be simplified by using 4M pages, at the expense
\ of requiring a modern processor variant and additional complexity
\ in later MMU management code.

   \ /section is the amount of memory that can be mapped with one page table
   mem-info-pa 4 + #)  dx  mov		\ Top of memory available to software
   /section 1- #       dx  add		\ Round up to a multiple of /section
   d# 22 #             dx  shr		\ Number of ptabs needed

   cr4      ax  mov    \ Try to turn on Page Size Extension Bit
   h# 10 #  ax  or
   ax       cr4 mov

   cr4      ax  mov    \ See if it worked
   h# 10 #  ax  and  0=  if

      \ Processor does not support 4M pages, so use page tables
      dx                  ax  mov	\ Copy of #ptabs
      d# 12 #             ax  shl	\ Number of bytes for page tables
      ax                  si  sub	\ Get memory for page tables

      \ Page Directory Entries
      si                  ax  mov
      pte-control #       ax  or	\ PDE contents
      bx                  di  mov	\ Base address
      dx                  cx  mov	\ Loop count (#ptabs)
      begin
         ax stos			\ pde for linear=physical page table
         /ptab # ax add			\ Point to next page table
      loopa

      \ Page Table Entries
      mem-info-pa 4 + #)     cx  mov	\ Top of memory available to software
      /page 1- #             cx  add	\ Round to a multiple of /page
      d# 12 #                cx  shr	\ #pages

      pte-control #          ax  mov	\ First PTE value (physical 0)
      si                     di  mov	\ Base address of first page table
      begin
         ax stos			\ Set PTE
         /page #  ax  add
      loopa

      d# 10 #                dx  shl	\ #pages mapped by ptabs
      dx                     cx  mov	\ Move into cx

      mem-info-pa 4 + #)     dx  mov	\ Top of memory available to software
      /page 1- #             dx  add	\ Round to a multiple of /page
      d# 12 #                dx  shr	\ #pages

      dx                     cx  sub	\ #ptes to zero
      ax                     ax  xor	\ Clear ax to make invalid PTE
      rep  ax  stos			\ Fill the leftovers


   else
      \ Use 4M pages.

      \ Page Directory Entries
      pte-control h# 80 + #  ax  mov	\ PDE for 4M page at 0
      bx                  di  mov	\ Base address
      dx                  cx  mov	\ Loop count (#ptabs)
      begin
         ax stos			\ pde for linear=physical page table
         /section # ax add		\ Point to next 4M section
      loopa
   then

[ifdef] rom-pa
   \ Page Directory Entry
   /ptab #             si  sub
   si                  bp  mov		\ Page table PA in EBP
   bp                  ax  mov
   pte-control #       ax  or		\ Page table PDE in EAX
   ax   rom-pa d# 22 rshift /l*  [bx]  mov  \ Set PDE for ROM page tables

   \ Page Table Entries

   \ create PTEs for the ROM version OFW
   rom-pa /page 1- invert land  pte-control + #       ax  mov
   bp                                                 di  mov
   rom-pa pte-mask land /page / /l* #                 di  add

   /rom /page / #		             cx  mov

   begin
      ax stos
      /page #  ax  add
   loopa
[then]

[ifdef] mem-info-pa
   si  mem-info-pa 1 la+ #)  mov	\ Report top of page table area
[then]

ascii P report
   \ enable paging
   bx              cr3  mov	\ Set Page Directory Base Register
   cr0		   ax   mov
   8000.0000 #     ax   or
   ax              cr0  mov	\ Turn on Paging Enable bit
ascii O report

   ret
end-code

end-assembling

writing paging.di
asm-base  here over -  0  " paging" write-dropin
ofd @ fclose

\ LICENSE_BEGIN
\ Copyright (c) 2006 FirmWorks
\ 
\ Permission is hereby granted, free of charge, to any person obtaining
\ a copy of this software and associated documentation files (the
\ "Software"), to deal in the Software without restriction, including
\ without limitation the rights to use, copy, modify, merge, publish,
\ distribute, sublicense, and/or sell copies of the Software, and to
\ permit persons to whom the Software is furnished to do so, subject to
\ the following conditions:
\ 
\ The above copyright notice and this permission notice shall be
\ included in all copies or substantial portions of the Software.
\ 
\ THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
\ EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
\ MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
\ NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
\ LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
\ OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
\ WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
\
\ LICENSE_END
