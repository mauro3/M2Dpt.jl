program M2Dpt

use mpi
use physics
use numerics

implicit none

integer                  :: i, j
real(8)                  :: tcpu1, tcpu2
integer                  :: stat(MPI_STATUS_SIZE)
integer                  :: prank
integer                  :: psize
integer                  :: code
integer                  :: comm2d
integer,parameter        :: tag=1111
integer,dimension(4)     :: neighbor
integer,parameter        :: NORTH=1, SOUTH=2, WEST=3, EAST=4
integer,parameter        :: ndims = 2
integer,dimension(ndims) :: dims, coords
logical                  :: reorder
logical,dimension(ndims) :: periods
integer                  :: nxp, nyp, mx, my
integer                  :: line_t, column_t
integer                  :: offset_x, offset_y

real(8)              :: dx, dy
real(8)              :: dVxDx, dVyDy
real(8), allocatable :: Vx(:,:)
real(8), allocatable :: Vy(:,:)
real(8), allocatable :: div(:,:)
real(8), allocatable :: xn(:), xc(:), yn(:), yc(:)

call MPI_INIT(code)
call MPI_COMM_SIZE(MPI_COMM_WORLD,psize,code)
call MPI_COMM_RANK(MPI_COMM_WORLD,prank,code)
call MPI_BARRIER(MPI_COMM_WORLD, code)

allocate(xn(nx+1))
allocate(xc(nx))
allocate(yn(ny+1))
allocate(yc(ny))

dx = Lx / real(nx,kind=8)
dy = Ly / real(ny,kind=8)

print*, dx, dy

do i = 1, nx+1
   xn(i) = (i-1)*dx
end do
do i = 1, nx
   xc(i) = (i-0.5)*dx
end do
do j = 1, ny+1
   yn(j) = (j-1)*dy
end do
do j = 1, ny
   yc(j) = (j-0.5)*dy
end do

tcpu1 = MPI_WTIME()


!Nombre de processus suivant x et y
dims(:) = 0
call MPI_DIMS_CREATE(psize,ndims,dims,code)
nxp = dims(1)
nyp = dims(2)

periods(1) = .false.
periods(2) = .false.
reorder    = .true.

call MPI_CART_CREATE(MPI_COMM_WORLD,ndims,dims,periods,reorder,comm2d,code)

neighbor(:) = MPI_PROC_NULL

!neighbors SOUTH and NORTH
call MPI_CART_SHIFT(comm2d,0,1,neighbor(NORTH),neighbor(SOUTH),code)
!neighbors WEST and EAST
call MPI_CART_SHIFT(comm2d,1,1,neighbor(WEST),neighbor(EAST),code)
!Get coordinates in the topology
call MPI_COMM_RANK(comm2d,prank,code)
call MPI_CART_COORDS(comm2d,prank,ndims,coords,code)

mx = nx/nxp
my = ny/nyp
offset_x = coords(1)*mx
offset_y = coords(2)*my

allocate(Vx(mx+1,my))
allocate(Vy(mx,my+1))
allocate(div(mx,my))
allocate(Exxc(mx,my))
allocate(Eyyc(mx,my))

print*, "proc : ",prank,": ",mx,"x",my
print*, "proc : ",prank,": coordinates : ", coords(:)
print*, "proc : ",prank,": offset : ", offset_x, offset_y
print*, "proc : ",prank,": neighbors   : ", neighbor(1:4)

call flush(6)
call MPI_BARRIER(MPI_COMM_WORLD, code)

!column type
call MPI_TYPE_CONTIGUOUS(mx+1,MPI_REAL8,column_t,code)
call MPI_TYPE_COMMIT(column_t,code)

!line type
call MPI_TYPE_VECTOR(my+1,1,mx+1,MPI_REAL8,line_t,code)
call MPI_TYPE_COMMIT(line_t,code)


do j = 1, my+1
   do i = 1, mx+1
      if (j <= my) Vx(i,j) =  Vbc * xn(offset_x+i) /Lx
      if (i <= mx) Vy(i,j) = -Vbc * yn(offset_y+j) /Ly
   end do
end do

!Send to neighbor EAST and receive from neighbor WEST
call MPI_SEND( vx(   1,my+1), 1, column_t, neighbor(EAST), tag, comm2d, code)
call MPI_RECV( vx(   1,   1), 1, column_t, neighbor(WEST), tag, comm2d, stat, code)
if (neighbor(EAST) >= 0) then
    call MPI_SENDRECV(vx(   1,my+1),1,column_t,neighbor(EAST),tag,&
                      vx(   1,   1),1,column_t,neighbor(WEST),tag,&
                      comm2d, stat, code)
end if

!Send to neighbor SOUTH and receive from neighbor NORTH
if (neighbor(SOUTH) >= 0) then
    call MPI_SENDRECV(vy(mx+1,   1),1,line_t,neighbor(SOUTH),tag, &
                      vy(   1,   1),1,line_t,neighbor(NORTH),tag, &
                      comm2d, stat, code)
end if

!Send to neighbor WEST and receive from neighbor EAST
if (neighbor(WEST) >= 0) then
    call MPI_SENDRECV(vx(   1,   1),1,column_t,neighbor(WEST),tag, &
                      vx(   1,my+1),1,column_t,neighbor(EAST),tag, &
                      comm2d, stat, code)
end if

!send to neighbor NORTH and receive from neighbor SOUTH
if (neighbor(NORTH) >= 0) then
    call MPI_SENDRECV(vy(   1,   1),1,line_t,neighbor(NORTH),tag, &
                      vy(mx+1,   1),1,line_t,neighbor(SOUTH),tag, &
                      comm2d, stat, code)
end if

do j=1,my
   do i=1,mx

      dVxdx = (Vx(i+1,j)-Vx(i,j))/dx
      dVydy = (Vy(i,j+1)-Vy(i,j))/dy

      div(i,j) = dVxdx + dVydy
      Exxc(i,j) = dVxdx - 0.5d0 * (dVxdx + dVydy)
      Eyyc(i,j) = dVydy - 0.5d0 * (dVxdx + dVydy)

   end do
end do

            end do
            end do

            do j=1,ny+1
            do i=1,nx+1
                Exyv(i,j) = 0.5d0*(  (Vx_exp(i,j+1)-Vx_exp(i,j))/dy  &
                                   + (Vy_exp(i+1,j)-Vy_exp(i,j))/dx )
            end do
            end do

            do j=1,ny
            do i=1,nx
                Exyc(i,j) = 0.25d0*(Exyv(i,j  )+Exyv(i+1,j  ) &
                                   +Exyv(i,j+1)+Exyv(i+1,j+1))
            end do
            end do



call flush(6)
call MPI_BARRIER(MPI_COMM_WORLD, code)
call plot(1, div)
call MPI_BARRIER(MPI_COMM_WORLD, code)
tcpu2 = MPI_WTIME()
if (prank == 0) &
   write(*,"(//10x,' CPU time = ', G15.3, ' sec' )") (tcpu2-tcpu1)*psize

call MPI_FINALIZE(code)
stop



contains

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine int2string( ival, fin)

    integer :: ival
    integer :: kk0, kk1, kk2, kk3, kk4
    character(len=4) :: fin
    character(len=1) :: aa,bb,cc,dd
    
    kk0  = ival
    kk1  = kk0/1000
    aa   = char(kk1 + 48)
    kk2  = (kk0 - kk1*1000)/100
    bb   = char(kk2 + 48)
    kk3  = (kk0 - (kk1*1000) - (kk2*100))/10
    cc   = char(kk3 + 48)
    kk4  = (kk0 - (kk1*1000) - (kk2*100) - (kk3*10))/1
    dd   = char(kk4 + 48)
    fin  = aa//bb//cc//dd

end subroutine int2string

subroutine plot(iplot, f)

integer :: iplot
real(8) :: f(:,:)
character(len=4) :: fin

call int2string( prank*1000+iplot, fin)
!write domains
open( 80, file = fin//".dat" )
   do i=1,mx
      do j=1,my
         write(80,"(3e10.2)") xc(offset_x+i), yc(offset_y+j), f(i,j)
      end do
      write(80,*) 
   end do
close(80)
   
!write master file
if (prank == 0) then
    open( 90, file = 'plot.gnu', position="append" )
    if ( iplot == 1 ) then
       rewind(90)
       write(90,*)"set surf"
    end if
    write(90,"(a)",advance='no')"splot '"//fin//".dat' w l"
    do j = 1, psize - 1
       call int2string( j*1000+iplot, fin)
       write(90,"(a)",advance='no')",'"//fin//".dat' w l" 
    end do
    write(90,*)
    close(90)
end if

end subroutine plot

end program M2Dpt
