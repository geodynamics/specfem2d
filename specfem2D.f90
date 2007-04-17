
!========================================================================
!
!                   S P E C F E M 2 D  Version 5.2
!                   ------------------------------
!
!                         Dimitri Komatitsch
!                     University of Pau, France
!
!                          (c) April 2007
!
!========================================================================

!====================================================================================
!
! An explicit 2D spectral element solver for the anelastic anisotropic wave equation
!
!====================================================================================

! If you use this code for your own research, please cite:
!
! @ARTICLE{KoTr99,
! author={D. Komatitsch and J. Tromp},
! title={Introduction to the spectral-element method for 3-{D} seismic wave propagation},
! journal={Geophys. J. Int.},
! year=1999,
! volume=139,
! number=3,
! pages={806-822},
! doi={10.1046/j.1365-246x.1999.00967.x}}
!
! @ARTICLE{KoVi98,
! author={D. Komatitsch and J. P. Vilotte},
! title={The spectral-element method: an efficient tool to simulate the seismic response of 2{D} and 3{D} geological structures},
! journal={Bull. Seismol. Soc. Am.},
! year=1998,
! volume=88,
! number=2,
! pages={368-392}}

!
! version 5.2, Dimitri Komatitsch, April 2007 :
!               - general fluid/solid implementation with any number, shape and orientation of
!                 matching edges
!               - absorbing edges with any normal vector
!               - general numbering of absorbing and acoustic free surface edges
!               - cleaned implementation of attenuation as in Carcione (1993)
!               - merged loops in the solver for efficiency
!               - simplified input of external model
!               - added CPU time information
!               - translated many comments from French to English
!
! version 5.1, Dimitri Komatitsch, January 2005 :
!               - more general mesher with any number of curved layers
!               - Dirac and Gaussian time sources and corresponding convolution routine
!               - option for acoustic medium instead of elastic
!               - receivers at any location, not only grid points
!               - moment-tensor source at any location, not only a grid point
!               - color snapshots
!               - more flexible DATA/Par_file with any number of comment lines
!               - Xsu scripts for seismograms
!               - subtract t0 from seismograms
!               - seismograms and snapshots in pressure in addition to vector field
!
! version 5.0, Dimitri Komatitsch, May 2004 :
!               - got rid of useless routines, suppressed commons etc.
!               - weak formulation based explicitly on stress tensor
!               - implementation of full anisotropy
!               - implementation of attenuation based on memory variables
!
! based on SPECFEM2D version 4.2, June 1998
! (c) by Dimitri Komatitsch, Harvard University, USA
! and Jean-Pierre Vilotte, Institut de Physique du Globe de Paris, France
!
! itself based on SPECFEM2D version 1.0, 1995
! (c) by Dimitri Komatitsch and Jean-Pierre Vilotte,
! Institut de Physique du Globe de Paris, France
!

! in case of an acoustic medium, a displacement potential Chi is used as in Chaljub and Valette,
! Geophysical Journal International, vol. 158, p. 131-141 (2004) and *NOT* a velocity potential
! as in Komatitsch and Tromp, Geophysical Journal International, vol. 150, p. 303-318 (2002).
! This permits acoustic-elastic coupling based on a non-iterative time scheme.
! Displacement is then: u = grad(Chi)
! Velocity is then: v = grad(Chi_dot)       (Chi_dot being the time derivative of Chi)
! and pressure is: p = - rho * Chi_dot_dot  (Chi_dot_dot being the time second derivative of Chi).
! The source in an acoustic element is a pressure source.

  program specfem2D

  implicit none

  include "constants.h"

  character(len=80) datlin

  integer :: source_type,time_function_type
  double precision :: x_source,z_source,xi_source,gamma_source,Mxx,Mzz,Mxz,f0,t0,factor,angleforce,hdur,hdur_gauss
  double precision, dimension(NDIM,NGLLX,NGLLZ) :: sourcearray

  double precision, dimension(:,:), allocatable :: coorg
  double precision, dimension(:), allocatable :: coorgread

! receiver information
  integer, dimension(:), allocatable :: ispec_selected_rec
  double precision, dimension(:), allocatable :: xi_receiver,gamma_receiver,st_xval,st_zval

! for seismograms
  double precision, dimension(:,:), allocatable :: sisux,sisuz
! vector field in an element
  double precision, dimension(NDIM,NGLLX,NGLLX) :: vector_field_element
! pressure in an element
  double precision, dimension(NGLLX,NGLLX) :: pressure_element

! to write seismograms in single precision SEP and double precision binary format
  real(kind=4), dimension(:), allocatable :: buffer_binary_single
  double precision, dimension(:), allocatable :: buffer_binary_double

  integer :: i,j,k,it,irec,ipoin,ip,id,nbpoin,inump,n,ispec,iedge,npoin,npgeo,iglob
  logical :: anyabs
  double precision :: dxd,dzd,valux,valuz,hlagrange,rhol,cosrot,sinrot,xi,gamma,x,z

! coefficients of the explicit Newmark time scheme
  integer NSTEP
  double precision deltatover2,deltatsquareover2,time,deltat

! Gauss-Lobatto-Legendre points and weights
  double precision, dimension(NGLLX) :: xigll,wxgll
  double precision, dimension(NGLLZ) :: zigll,wzgll

! derivatives of Lagrange polynomials
  double precision, dimension(NGLLX,NGLLX) :: hprime_xx,hprimewgll_xx
  double precision, dimension(NGLLZ,NGLLZ) :: hprime_zz,hprimewgll_zz

! Jacobian matrix and determinant
  double precision :: xixl,xizl,gammaxl,gammazl,jacobianl

! material properties of the elastic medium
  double precision :: mul_relaxed,lambdal_relaxed,cpsquare

  double precision, dimension(:,:), allocatable :: coord,accel_elastic,veloc_elastic,displ_elastic, &
    flagrange,xinterp,zinterp,Uxinterp,Uzinterp,elastcoef,vector_field_display

! for acoustic medium
  double precision, dimension(:), allocatable :: potential_dot_dot_acoustic,potential_dot_acoustic,potential_acoustic

  double precision, dimension(:), allocatable :: rmass_inverse_elastic,rmass_inverse_acoustic,density,displread,velocread,accelread

  double precision, dimension(:,:,:), allocatable :: vpext,vsext,rhoext
  double precision :: previous_vsext

  double precision, dimension(:,:,:), allocatable :: shape2D,shape2D_display,xix,xiz,gammax,gammaz,jacobian

  double precision, dimension(:,:,:,:), allocatable :: dershape2D,dershape2D_display

  integer, dimension(:,:,:), allocatable :: ibool
  integer, dimension(:,:), allocatable  :: knods
  integer, dimension(:), allocatable :: kmato,numabs,ispecnum_acoustic_surface,iedgenum_acoustic_surface, &
     ibegin_bottom,iend_bottom,ibegin_top,iend_top,jbegin_left,jend_left,jbegin_right,jend_right

  integer ispec_selected_source,iglob_source,ix_source,iz_source
  double precision a,displnorm_all
  double precision, dimension(:), allocatable :: source_time_function
  double precision, external :: erf

  double precision :: vpmin,vpmax

  integer :: colors,numbers,subsamp,imagetype,NTSTEP_BETWEEN_OUTPUT_INFO,nrec,seismotype
  integer :: numat,ngnod,nspec,pointsdisp,nelemabs,nelem_acoustic_surface,ispecabs

  logical interpol,meshvect,modelvect,boundvect,assign_external_model,initialfield, &
    outputgrid,gnuplot,TURN_ANISOTROPY_ON,TURN_ATTENUATION_ON,output_postscript_snapshot,output_color_image, &
    plot_lowerleft_corner_only

  double precision :: cutsnaps,sizemax_arrows,anglerec,xirec,gammarec

! for absorbing and acoustic free surface conditions
  integer :: ispec_acoustic_surface,inum,numabsread,numacoustread,iedgeacoustread
  logical :: codeabsread(4)
  double precision :: nx,nz,weight,xxi,zgamma

  logical, dimension(:,:), allocatable  :: codeabs

! for attenuation
  integer nspec_allocate
  double precision :: deltatsquare,deltatcube,deltatfourth,twelvedeltat,fourdeltatsquare

  double precision, dimension(:,:,:), allocatable :: &
    e1_mech1,e11_mech1,e13_mech1,e1_mech2,e11_mech2,e13_mech2, &
    dux_dxl_n,duz_dzl_n,duz_dxl_n,dux_dzl_n,dux_dxl_np1,duz_dzl_np1,duz_dxl_np1,dux_dzl_np1

! for fluid/solid coupling and edge detection
  logical, dimension(:), allocatable :: elastic
  integer, dimension(NEDGES) :: i_begin,j_begin,i_end,j_end
  integer, dimension(NGLLX,NEDGES) :: ivalue,jvalue,ivalue_inverse,jvalue_inverse
  integer, dimension(:), allocatable :: fluid_solid_acoustic_ispec,fluid_solid_acoustic_iedge, &
                                        fluid_solid_elastic_ispec,fluid_solid_elastic_iedge
  integer :: num_fluid_solid_edges,num_fluid_solid_edges_alloc,ispec_acoustic,ispec_elastic, &
             iedge_acoustic,iedge_elastic,ipoin1D,iglob2
  logical :: any_acoustic,any_elastic,coupled_acoustic_elastic
  double precision :: displ_x,displ_z,displ_n,zxi,xgamma,jacobian1D,pressure

! for color images
  integer :: NX_IMAGE_color,NZ_IMAGE_color,iplus1,jplus1,iminus1,jminus1,count_passes
  double precision :: xmin_color_image,xmax_color_image, &
    zmin_color_image,zmax_color_image,size_pixel_horizontal,size_pixel_vertical
  integer, dimension(:,:), allocatable :: iglob_image_color,copy_iglob_image_color
  double precision, dimension(:,:), allocatable :: image_color_data

! timing information for the stations
  character(len=MAX_LENGTH_STATION_NAME), allocatable, dimension(:) :: station_name
  character(len=MAX_LENGTH_NETWORK_NAME), allocatable, dimension(:) :: network_name

! title of the plot
  character(len=60) simulation_title

! Lagrange interpolators at receivers
  double precision, dimension(:), allocatable :: hxir,hgammar,hpxir,hpgammar
  double precision, dimension(:,:), allocatable :: hxir_store,hgammar_store

! for Lagrange interpolants
  double precision, external :: hgll

! timer to count elapsed time
  character(len=8) datein
  character(len=10) timein
  character(len=5)  :: zone
  integer, dimension(8) :: time_values
  integer ihours,iminutes,iseconds,int_tCPU
  double precision :: time_start,time_end,tCPU

!***********************************************************************
!
!             i n i t i a l i z a t i o n    p h a s e
!
!***********************************************************************

  open (IIN,file='OUTPUT_FILES/Database')

! determine if we write to file instead of standard output
  if(IOUT /= ISTANDARD_OUTPUT) open (IOUT,file='simulation_results.txt')

!
!---  read job title and skip remaining titles of the input file
!
  read(IIN,"(a80)") datlin
  read(IIN,"(a80)") datlin
  read(IIN,"(a80)") datlin
  read(IIN,"(a80)") datlin
  read(IIN,"(a80)") datlin
  read(IIN,"(a50)") simulation_title

!
!---- print the date, time and start-up banner
!
  call datim(simulation_title)

  write(IOUT,*)
  write(IOUT,*)
  write(IOUT,*) '*********************'
  write(IOUT,*) '****             ****'
  write(IOUT,*) '****  SPECFEM2D  ****'
  write(IOUT,*) '****             ****'
  write(IOUT,*) '*********************'

!
!---- read parameters from input file
!

  read(IIN,"(a80)") datlin
  read(IIN,*) npgeo

  read(IIN,"(a80)") datlin
  read(IIN,*) gnuplot,interpol

  read(IIN,"(a80)") datlin
  read(IIN,*) NTSTEP_BETWEEN_OUTPUT_INFO

  read(IIN,"(a80)") datlin
  read(IIN,*) output_postscript_snapshot,output_color_image,colors,numbers

  read(IIN,"(a80)") datlin
  read(IIN,*) meshvect,modelvect,boundvect,cutsnaps,subsamp,sizemax_arrows
  cutsnaps = cutsnaps / 100.d0

  read(IIN,"(a80)") datlin
  read(IIN,*) anglerec

  read(IIN,"(a80)") datlin
  read(IIN,*) initialfield

  read(IIN,"(a80)") datlin
  read(IIN,*) seismotype,imagetype
  if(seismotype < 1 .or. seismotype > 4) stop 'Wrong type for seismogram output'
  if(imagetype < 1 .or. imagetype > 4) stop 'Wrong type for snapshots'

  read(IIN,"(a80)") datlin
  read(IIN,*) assign_external_model,outputgrid,TURN_ANISOTROPY_ON,TURN_ATTENUATION_ON

!---- check parameters read
  write(IOUT,200) npgeo,NDIM
  write(IOUT,600) NTSTEP_BETWEEN_OUTPUT_INFO,colors,numbers
  write(IOUT,700) seismotype,anglerec
  write(IOUT,750) initialfield,assign_external_model,TURN_ANISOTROPY_ON,TURN_ATTENUATION_ON,outputgrid
  write(IOUT,800) imagetype,100.d0*cutsnaps,subsamp

!---- read time step
  read(IIN,"(a80)") datlin
  read(IIN,*) NSTEP,deltat
  write(IOUT,703) NSTEP,deltat,NSTEP*deltat

!
!----  read source information
!
  read(IIN,"(a80)") datlin
  read(IIN,*) source_type,time_function_type,x_source,z_source,f0,t0,factor,angleforce,Mxx,Mzz,Mxz

!
!-----  check the input
!
 if(.not. initialfield) then
   if (source_type == 1) then
     write(IOUT,212) x_source,z_source,f0,t0,factor,angleforce
   else if(source_type == 2) then
     write(IOUT,222) x_source,z_source,f0,t0,factor,Mxx,Mzz,Mxz
   else
     stop 'Unknown source type number !'
   endif
 endif

! for the source time function
  a = pi*pi*f0*f0

!-----  convert angle from degrees to radians
  angleforce = angleforce * pi / 180.d0

!
!---- read the spectral macrobloc nodal coordinates
!
  allocate(coorg(NDIM,npgeo))

  ipoin = 0
  read(IIN,"(a80)") datlin
  allocate(coorgread(NDIM))
  do ip = 1,npgeo
   read(IIN,*) ipoin,(coorgread(id),id =1,NDIM)
   if(ipoin<1 .or. ipoin>npgeo) stop 'Wrong control point number'
   coorg(:,ipoin) = coorgread
  enddo
  deallocate(coorgread)

!
!---- read the basic properties of the spectral elements
!
  read(IIN,"(a80)") datlin
  read(IIN,*) numat,ngnod,nspec,pointsdisp,plot_lowerleft_corner_only
  read(IIN,"(a80)") datlin
  read(IIN,*) nelemabs,nelem_acoustic_surface

!
!---- allocate arrays
!
  allocate(shape2D(ngnod,NGLLX,NGLLZ))
  allocate(dershape2D(NDIM,ngnod,NGLLX,NGLLZ))
  allocate(shape2D_display(ngnod,pointsdisp,pointsdisp))
  allocate(dershape2D_display(NDIM,ngnod,pointsdisp,pointsdisp))
  allocate(xix(NGLLX,NGLLZ,nspec))
  allocate(xiz(NGLLX,NGLLZ,nspec))
  allocate(gammax(NGLLX,NGLLZ,nspec))
  allocate(gammaz(NGLLX,NGLLZ,nspec))
  allocate(jacobian(NGLLX,NGLLZ,nspec))
  allocate(flagrange(NGLLX,pointsdisp))
  allocate(xinterp(pointsdisp,pointsdisp))
  allocate(zinterp(pointsdisp,pointsdisp))
  allocate(Uxinterp(pointsdisp,pointsdisp))
  allocate(Uzinterp(pointsdisp,pointsdisp))
  allocate(density(numat))
  allocate(elastcoef(4,numat))
  allocate(kmato(nspec))
  allocate(knods(ngnod,nspec))
  allocate(ibool(NGLLX,NGLLZ,nspec))
  allocate(elastic(nspec))

! --- allocate arrays for absorbing boundary conditions
  if(nelemabs <= 0) then
    nelemabs = 1
    anyabs = .false.
  else
    anyabs = .true.
  endif
  allocate(numabs(nelemabs))
  allocate(codeabs(4,nelemabs))

  allocate(ibegin_bottom(nelemabs))
  allocate(iend_bottom(nelemabs))
  allocate(ibegin_top(nelemabs))
  allocate(iend_top(nelemabs))

  allocate(jbegin_left(nelemabs))
  allocate(jend_left(nelemabs))
  allocate(jbegin_right(nelemabs))
  allocate(jend_right(nelemabs))

! --- allocate array for free surface condition in acoustic medium
  if(nelem_acoustic_surface <= 0) then
    nelem_acoustic_surface = 0
    allocate(ispecnum_acoustic_surface(1))
    allocate(iedgenum_acoustic_surface(1))
  else
    allocate(ispecnum_acoustic_surface(nelem_acoustic_surface))
    allocate(iedgenum_acoustic_surface(nelem_acoustic_surface))
  endif

!
!---- print element group main parameters
!
  write(IOUT,107)
  write(IOUT,207) nspec,ngnod,NGLLX,NGLLZ,NGLLX*NGLLZ,pointsdisp,numat,nelemabs

! set up Gauss-Lobatto-Legendre derivation matrices
  call define_derivation_matrices(xigll,zigll,wxgll,wzgll,hprime_xx,hprime_zz,hprimewgll_xx,hprimewgll_zz)

!
!---- read the material properties
!
  call gmat01(density,elastcoef,numat)

!
!----  read spectral macrobloc data
!
  n = 0
  read(IIN,"(a80)") datlin
  do ispec = 1,nspec
    read(IIN,*) n,kmato(n),(knods(k,n), k=1,ngnod)
  enddo

!
!----  determine if each spectral element is elastic or acoustic
!
  any_acoustic = .false.
  any_elastic = .false.
  do ispec = 1,nspec
    mul_relaxed = elastcoef(2,kmato(ispec))
    if(mul_relaxed < TINYVAL) then
      elastic(ispec) = .false.
      any_acoustic = .true.
    else
      elastic(ispec) = .true.
      any_elastic = .true.
    endif
  enddo

  if(TURN_ATTENUATION_ON) then
    nspec_allocate = nspec
  else
    nspec_allocate = 1
  endif

! allocate memory variables for attenuation
  allocate(e1_mech1(NGLLX,NGLLZ,nspec_allocate))
  allocate(e11_mech1(NGLLX,NGLLZ,nspec_allocate))
  allocate(e13_mech1(NGLLX,NGLLZ,nspec_allocate))
  allocate(e1_mech2(NGLLX,NGLLZ,nspec_allocate))
  allocate(e11_mech2(NGLLX,NGLLZ,nspec_allocate))
  allocate(e13_mech2(NGLLX,NGLLZ,nspec_allocate))
  allocate(dux_dxl_n(NGLLX,NGLLZ,nspec_allocate))
  allocate(duz_dzl_n(NGLLX,NGLLZ,nspec_allocate))
  allocate(duz_dxl_n(NGLLX,NGLLZ,nspec_allocate))
  allocate(dux_dzl_n(NGLLX,NGLLZ,nspec_allocate))
  allocate(dux_dxl_np1(NGLLX,NGLLZ,nspec_allocate))
  allocate(duz_dzl_np1(NGLLX,NGLLZ,nspec_allocate))
  allocate(duz_dxl_np1(NGLLX,NGLLZ,nspec_allocate))
  allocate(dux_dzl_np1(NGLLX,NGLLZ,nspec_allocate))

!
!----  read absorbing boundary data
!
  if(anyabs) then
    read(IIN,"(a80)") datlin
    do inum = 1,nelemabs
      read(IIN,*) numabsread,codeabsread(1),codeabsread(2),codeabsread(3),codeabsread(4)
      if(numabsread < 1 .or. numabsread > nspec) stop 'Wrong absorbing element number'
      numabs(inum) = numabsread
      codeabs(IBOTTOM,inum) = codeabsread(1)
      codeabs(IRIGHT,inum) = codeabsread(2)
      codeabs(ITOP,inum) = codeabsread(3)
      codeabs(ILEFT,inum) = codeabsread(4)
    enddo
    write(IOUT,*)
    write(IOUT,*) 'Number of absorbing elements: ',nelemabs
  endif

!
!----  read acoustic free surface data
!
  if(nelem_acoustic_surface > 0) then
    read(IIN,"(a80)") datlin
    do inum = 1,nelem_acoustic_surface
      read(IIN,*) numacoustread,iedgeacoustread
      if(numacoustread < 1 .or. numacoustread > nspec) stop 'Wrong acoustic free surface element number'
      if(iedgeacoustread < 1 .or. iedgeacoustread > NEDGES) stop 'Wrong acoustic free surface edge number'
      ispecnum_acoustic_surface(inum) = numacoustread
      iedgenum_acoustic_surface(inum) = iedgeacoustread
    enddo
    write(IOUT,*)
    write(IOUT,*) 'Number of free surface elements: ',nelem_acoustic_surface
  endif

!
!---- close input file
!
  close(IIN)

!
!---- compute shape functions and their derivatives for SEM grid
!
  do j = 1,NGLLZ
    do i = 1,NGLLX
      call define_shape_functions(shape2D(:,i,j),dershape2D(:,:,i,j),xigll(i),zigll(j),ngnod)
    enddo
  enddo

!
!---- generate the global numbering
!

! "slow and clean" or "quick and dirty" version
  if(FAST_NUMBERING) then
    call createnum_fast(knods,ibool,shape2D,coorg,npoin,npgeo,nspec,ngnod)
  else
    call createnum_slow(knods,ibool,npoin,nspec,ngnod)
  endif

!---- compute shape functions and their derivatives for regular !interpolated display grid
  do j = 1,pointsdisp
    do i = 1,pointsdisp
      xirec  = 2.d0*dble(i-1)/dble(pointsdisp-1) - 1.d0
      gammarec  = 2.d0*dble(j-1)/dble(pointsdisp-1) - 1.d0
      call define_shape_functions(shape2D_display(:,i,j),dershape2D_display(:,:,i,j),xirec,gammarec,ngnod)
    enddo
  enddo

!---- compute Lagrange interpolants on a regular interpolated grid in (xi,gamma)
!---- for display (assumes NGLLX = NGLLZ)
  do j=1,NGLLX
    do i=1,pointsdisp
      xirec  = 2.d0*dble(i-1)/dble(pointsdisp-1) - 1.d0
      flagrange(j,i) = hgll(j-1,xirec,xigll,NGLLX)
    enddo
  enddo

! read total number of receivers
  open(unit=IIN,file='DATA/STATIONS',status='old')
  read(IIN,*) nrec
  close(IIN)

  write(IOUT,*)
  write(IOUT,*) 'Total number of receivers = ',nrec
  write(IOUT,*)

  if(nrec < 1) stop 'need at least one receiver'

! allocate seismogram arrays
  allocate(sisux(NSTEP,nrec))
  allocate(sisuz(NSTEP,nrec))

! to write seismograms in single precision SEP and double precision binary format
  allocate(buffer_binary_single(NSTEP*nrec))
  allocate(buffer_binary_double(NSTEP*nrec))

! receiver information
  allocate(ispec_selected_rec(nrec))
  allocate(st_xval(nrec))
  allocate(st_zval(nrec))
  allocate(xi_receiver(nrec))
  allocate(gamma_receiver(nrec))
  allocate(station_name(nrec))
  allocate(network_name(nrec))

! allocate 1-D Lagrange interpolators and derivatives
  allocate(hxir(NGLLX))
  allocate(hpxir(NGLLX))
  allocate(hgammar(NGLLZ))
  allocate(hpgammar(NGLLZ))

! allocate Lagrange interpolators for receivers
  allocate(hxir_store(nrec,NGLLX))
  allocate(hgammar_store(nrec,NGLLZ))

! allocate other global arrays
  allocate(coord(NDIM,npoin))

! to display acoustic elements
  allocate(vector_field_display(NDIM,npoin))

  if(assign_external_model) then
    allocate(vpext(NGLLX,NGLLZ,nspec))
    allocate(vsext(NGLLX,NGLLZ,nspec))
    allocate(rhoext(NGLLX,NGLLZ,nspec))
  else
    allocate(vpext(1,1,1))
    allocate(vsext(1,1,1))
    allocate(rhoext(1,1,1))
  endif

!
!----  set the coordinates of the points of the global grid
!
  do ispec = 1,nspec
    do j = 1,NGLLZ
      do i = 1,NGLLX

        xi = xigll(i)
        gamma = zigll(j)

        call recompute_jacobian(xi,gamma,x,z,xixl,xizl,gammaxl,gammazl,jacobianl,coorg,knods,ispec,ngnod,nspec,npgeo)

        coord(1,ibool(i,j,ispec)) = x
        coord(2,ibool(i,j,ispec)) = z

        xix(i,j,ispec) = xixl
        xiz(i,j,ispec) = xizl
        gammax(i,j,ispec) = gammaxl
        gammaz(i,j,ispec) = gammazl
        jacobian(i,j,ispec) = jacobianl

      enddo
    enddo
  enddo

!
!--- save the grid of points in a file
!
  if(outputgrid) then
    write(IOUT,*)
    write(IOUT,*) 'Saving the grid in a text file...'
    write(IOUT,*)
    open(unit=55,file='OUTPUT_FILES/grid_points_and_model.txt',status='unknown')
    write(55,*) npoin
    do n = 1,npoin
      write(55,*) (coord(i,n), i=1,NDIM)
    enddo
    close(55)
  endif

!
!-----   plot the GLL mesh in a Gnuplot file
!
  if(gnuplot) call plotgll(knods,ibool,coorg,coord,npoin,npgeo,ngnod,nspec)

!
!----  assign external velocity and density model if needed
!
  if(assign_external_model) then
    write(IOUT,*)
    write(IOUT,*) 'Assigning external velocity and density model...'
    write(IOUT,*)
    if(TURN_ANISOTROPY_ON .or. TURN_ATTENUATION_ON) &
         stop 'cannot have anisotropy nor attenuation if external model in current version'
    any_acoustic = .false.
    any_elastic = .false.
    do ispec = 1,nspec
      previous_vsext = -1.d0
      do j = 1,NGLLZ
        do i = 1,NGLLX
          iglob = ibool(i,j,ispec)
          call define_external_model(coord(1,iglob),coord(2,iglob),kmato(ispec), &
                                         rhoext(i,j,ispec),vpext(i,j,ispec),vsext(i,j,ispec))
! stop if the same element is assigned both acoustic and elastic points in external model
          if(.not. (i == 1 .and. j == 1) .and. &
            ((vsext(i,j,ispec) >= TINYVAL .and. previous_vsext < TINYVAL) .or. &
             (vsext(i,j,ispec) < TINYVAL .and. previous_vsext >= TINYVAL)))  &
                stop 'external velocity model cannot be both fluid and solid inside the same spectral element'
          if(vsext(i,j,ispec) < TINYVAL) then
            elastic(ispec) = .false.
            any_acoustic = .true.
          else
            elastic(ispec) = .true.
            any_elastic = .true.
          endif
          previous_vsext = vsext(i,j,ispec)
        enddo
      enddo
    enddo
  endif

!
!----  perform basic checks on parameters read
!

! for acoustic
  if(TURN_ANISOTROPY_ON .and. .not. any_elastic) stop 'cannot have anisotropy if acoustic simulation only'

  if(TURN_ATTENUATION_ON .and. .not. any_elastic) stop 'currently cannot have attenuation if acoustic simulation only'

! for attenuation
  if(TURN_ANISOTROPY_ON .and. TURN_ATTENUATION_ON) stop 'cannot have anisotropy and attenuation both turned on in current version'

!
!----   define coefficients of the Newmark time scheme
!
  deltatover2 = HALF*deltat
  deltatsquareover2 = HALF*deltat*deltat

!---- define actual location of source and receivers
  if(source_type == 1) then
! collocated force source
    call locate_source_force(coord,ibool,npoin,nspec,x_source,z_source,source_type, &
      ix_source,iz_source,ispec_selected_source,iglob_source)

! check that acoustic source is not exactly on the free surface because pressure is zero there
    do ispec_acoustic_surface = 1,nelem_acoustic_surface
      ispec = ispecnum_acoustic_surface(ispec_acoustic_surface)
      iedge = iedgenum_acoustic_surface(ispec_acoustic_surface)
      if(.not. elastic(ispec) .and. ispec == ispec_selected_source) then
        if((iedge == IBOTTOM .and. iz_source == 1) .or. &
           (iedge == ITOP .and. iz_source == NGLLZ) .or. &
           (iedge == ILEFT .and. ix_source == 1) .or. &
           (iedge == IRIGHT .and. ix_source == NGLLX)) &
          stop 'an acoustic source cannot be located exactly on the free surface because pressure is zero there'
      endif
    enddo

  else if(source_type == 2) then
! moment-tensor source
    call locate_source_moment_tensor(ibool,coord,nspec,npoin,xigll,zigll,x_source,z_source, &
               ispec_selected_source,xi_source,gamma_source,coorg,knods,ngnod,npgeo)

! compute source array for moment-tensor source
    call compute_arrays_source(ispec_selected_source,xi_source,gamma_source,sourcearray, &
               Mxx,Mzz,Mxz,xix,xiz,gammax,gammaz,xigll,zigll,nspec)

  else
    stop 'incorrect source type'
  endif


! locate receivers in the mesh
  call locate_receivers(ibool,coord,nspec,npoin,xigll,zigll,nrec,st_xval,st_zval,ispec_selected_rec, &
                 xi_receiver,gamma_receiver,station_name,network_name,x_source,z_source,coorg,knods,ngnod,npgeo)

! check if acoustic receiver is exactly on the free surface because pressure is zero there
  do ispec_acoustic_surface = 1,nelem_acoustic_surface
    ispec = ispecnum_acoustic_surface(ispec_acoustic_surface)
    iedge = iedgenum_acoustic_surface(ispec_acoustic_surface)
    do irec = 1,nrec
      if(.not. elastic(ispec) .and. ispec == ispec_selected_rec(irec)) then
         if((iedge == IBOTTOM .and. gamma_receiver(irec) < -0.99d0) .or. &
            (iedge == ITOP .and. gamma_receiver(irec) > 0.99d0) .or. &
            (iedge == ILEFT .and. xi_receiver(irec) < -0.99d0) .or. &
            (iedge == IRIGHT .and. xi_receiver(irec) > 0.99d0)) then
          if(seismotype == 4) then
            stop 'an acoustic pressure receiver cannot be located exactly on the free surface because pressure is zero there'
          else
            print *, '**********************************************************************'
            print *, '*** Warning: acoustic receiver located exactly on the free surface ***'
            print *, '*** Warning: tangential component will be zero there               ***'
            print *, '**********************************************************************'
            print *
          endif
        endif
      endif
    enddo
  enddo

! define and store Lagrange interpolators at all the receivers
  do irec = 1,nrec
    call lagrange_any(xi_receiver(irec),NGLLX,xigll,hxir,hpxir)
    call lagrange_any(gamma_receiver(irec),NGLLZ,zigll,hgammar,hpgammar)
    hxir_store(irec,:) = hxir(:)
    hgammar_store(irec,:) = hgammar(:)
  enddo

! displacement, velocity, acceleration and inverse of the mass matrix for elastic elements
  if(any_elastic) then
    allocate(displ_elastic(NDIM,npoin))
    allocate(veloc_elastic(NDIM,npoin))
    allocate(accel_elastic(NDIM,npoin))
    allocate(rmass_inverse_elastic(npoin))
  else
! allocate unused arrays with fictitious size
    allocate(displ_elastic(1,1))
    allocate(veloc_elastic(1,1))
    allocate(accel_elastic(1,1))
    allocate(rmass_inverse_elastic(1))
  endif

! potential, its first and second derivative, and inverse of the mass matrix for acoustic elements
  if(any_acoustic) then
    allocate(potential_acoustic(npoin))
    allocate(potential_dot_acoustic(npoin))
    allocate(potential_dot_dot_acoustic(npoin))
    allocate(rmass_inverse_acoustic(npoin))
  else
! allocate unused arrays with fictitious size
    allocate(potential_acoustic(1))
    allocate(potential_dot_acoustic(1))
    allocate(potential_dot_dot_acoustic(1))
    allocate(rmass_inverse_acoustic(1))
  endif

!
!---- build the global mass matrix and invert it once and for all
!
  if(any_elastic) rmass_inverse_elastic(:) = ZERO
  if(any_acoustic) rmass_inverse_acoustic(:) = ZERO
  do ispec = 1,nspec
    do j = 1,NGLLZ
      do i = 1,NGLLX
        iglob = ibool(i,j,ispec)
! if external density model
        if(assign_external_model) then
          rhol = rhoext(i,j,ispec)
          cpsquare = vpext(i,j,ispec)**2
        else
          rhol = density(kmato(ispec))
          lambdal_relaxed = elastcoef(1,kmato(ispec))
          mul_relaxed = elastcoef(2,kmato(ispec))
          cpsquare = (lambdal_relaxed + 2.d0*mul_relaxed) / rhol
        endif
! for acoustic medium
        if(elastic(ispec)) then
          rmass_inverse_elastic(iglob) = rmass_inverse_elastic(iglob) + wxgll(i)*wzgll(j)*rhol*jacobian(i,j,ispec)
        else
          rmass_inverse_acoustic(iglob) = rmass_inverse_acoustic(iglob) + wxgll(i)*wzgll(j)*jacobian(i,j,ispec) / cpsquare
        endif
      enddo
    enddo
  enddo

! fill mass matrix with fictitious non-zero values to make sure it can be inverted globally
  if(any_elastic) where(rmass_inverse_elastic <= 0.d0) rmass_inverse_elastic = 1.d0
  if(any_acoustic) where(rmass_inverse_acoustic <= 0.d0) rmass_inverse_acoustic = 1.d0

! compute the inverse of the mass matrix
  if(any_elastic) rmass_inverse_elastic(:) = 1 / rmass_inverse_elastic(:)
  if(any_acoustic) rmass_inverse_acoustic(:) = 1 / rmass_inverse_acoustic(:)

! check the mesh, stability and number of points per wavelength
  call checkgrid(vpext,vsext,rhoext,density,elastcoef,ibool,kmato,coord,npoin,vpmin,vpmax, &
                 assign_external_model,nspec,numat,deltat,f0,t0,initialfield,time_function_type, &
                 coorg,xinterp,zinterp,shape2D_display,knods,simulation_title,npgeo,pointsdisp,ngnod,any_elastic)

! convert receiver angle to radians
  anglerec = anglerec * pi / 180.d0

!
!---- for color images
!

  if(output_color_image) then

! horizontal size of the image
  xmin_color_image = minval(coord(1,:))
  xmax_color_image = maxval(coord(1,:))

! vertical size of the image, slightly increase it to go beyond maximum topography
  zmin_color_image = minval(coord(2,:))
  zmax_color_image = maxval(coord(2,:))
  zmax_color_image = zmin_color_image + 1.05d0 * (zmax_color_image - zmin_color_image)

! compute number of pixels in the horizontal direction based on typical number
! of spectral elements in a given direction (may give bad results for very elongated models)
  NX_IMAGE_color = nint(sqrt(dble(npgeo))) * (NGLLX-1) + 1

! compute number of pixels in the vertical direction based on ratio of sizes
  NZ_IMAGE_color = nint(NX_IMAGE_color * (zmax_color_image - zmin_color_image) / (xmax_color_image - xmin_color_image))

! convert pixel sizes to even numbers because easier to reduce size, create MPEG movies in postprocessing
  NX_IMAGE_color = 2 * (NX_IMAGE_color / 2)
  NZ_IMAGE_color = 2 * (NZ_IMAGE_color / 2)

! allocate an array for image data
  allocate(image_color_data(NX_IMAGE_color,NZ_IMAGE_color))

! allocate an array for the grid point that corresponds to a given image data point
  allocate(iglob_image_color(NX_IMAGE_color,NZ_IMAGE_color))
  allocate(copy_iglob_image_color(NX_IMAGE_color,NZ_IMAGE_color))

! create all the pixels
  write(IOUT,*)
  write(IOUT,*) 'locating all the pixels of color images'

  size_pixel_horizontal = (xmax_color_image - xmin_color_image) / dble(NX_IMAGE_color-1)
  size_pixel_vertical = (zmax_color_image - zmin_color_image) / dble(NZ_IMAGE_color-1)

  iglob_image_color(:,:) = -1

! loop on all the grid points to map them to a pixel in the image
      do n=1,npoin

! compute the coordinates of this pixel
      i = nint((coord(1,n) - xmin_color_image) / size_pixel_horizontal + 1)
      j = nint((coord(2,n) - zmin_color_image) / size_pixel_vertical + 1)

! avoid edge effects
      if(i < 1) i = 1
      if(i > NX_IMAGE_color) i = NX_IMAGE_color

      if(j < 1) j = 1
      if(j > NZ_IMAGE_color) j = NZ_IMAGE_color

! assign this point to this pixel
      iglob_image_color(i,j) = n

      enddo

! locate missing pixels based on a minimum distance criterion
! cannot do more than two iterations typically because some pixels must never be found
! because they do not exist (for instance if they are located above topography)
  do count_passes = 1,2

  print *,'pass ',count_passes,' to locate the missing pixels of color images'

  copy_iglob_image_color(:,:) = iglob_image_color(:,:)

  do j = 1,NZ_IMAGE_color
    do i = 1,NX_IMAGE_color

      if(copy_iglob_image_color(i,j) == -1) then

        iplus1 = i + 1
        iminus1 = i - 1

        jplus1 = j + 1
        jminus1 = j - 1

! avoid edge effects
        if(iminus1 < 1) iminus1 = 1
        if(iplus1 > NX_IMAGE_color) iplus1 = NX_IMAGE_color

        if(jminus1 < 1) jminus1 = 1
        if(jplus1 > NZ_IMAGE_color) jplus1 = NZ_IMAGE_color

! use neighbors of this pixel to fill the holes

! horizontal
        if(copy_iglob_image_color(iplus1,j) /= -1) then
          iglob_image_color(i,j) = copy_iglob_image_color(iplus1,j)

        else if(copy_iglob_image_color(iminus1,j) /= -1) then
          iglob_image_color(i,j) = copy_iglob_image_color(iminus1,j)

! vertical
        else if(copy_iglob_image_color(i,jplus1) /= -1) then
          iglob_image_color(i,j) = copy_iglob_image_color(i,jplus1)

        else if(copy_iglob_image_color(i,jminus1) /= -1) then
          iglob_image_color(i,j) = copy_iglob_image_color(i,jminus1)

! diagonal
        else if(copy_iglob_image_color(iminus1,jminus1) /= -1) then
          iglob_image_color(i,j) = copy_iglob_image_color(iminus1,jminus1)

        else if(copy_iglob_image_color(iplus1,jminus1) /= -1) then
          iglob_image_color(i,j) = copy_iglob_image_color(iplus1,jminus1)

        else if(copy_iglob_image_color(iminus1,jplus1) /= -1) then
          iglob_image_color(i,j) = copy_iglob_image_color(iminus1,jplus1)

        else if(copy_iglob_image_color(iplus1,jplus1) /= -1) then
          iglob_image_color(i,j) = copy_iglob_image_color(iplus1,jplus1)

        endif

      endif

    enddo
  enddo

  enddo

  deallocate(copy_iglob_image_color)

  write(IOUT,*) 'done locating all the pixels of color images'

  endif

!
!---- initialize seismograms
!
  sisux = ZERO
  sisuz = ZERO

  cosrot = cos(anglerec)
  sinrot = sin(anglerec)

! initialize arrays to zero
  displ_elastic = ZERO
  veloc_elastic = ZERO
  accel_elastic = ZERO

  potential_acoustic = ZERO
  potential_dot_acoustic = ZERO
  potential_dot_dot_acoustic = ZERO

!
!----  read initial fields from external file if needed
!
  if(initialfield) then
    write(IOUT,*)
    write(IOUT,*) 'Reading initial fields from external file...'
    write(IOUT,*)
    if(any_acoustic) stop 'initial field currently implemented for purely elastic simulation only'
    open(unit=55,file='OUTPUT_FILES/wavefields.txt',status='unknown')
    read(55,*) nbpoin
    if(nbpoin /= npoin) stop 'Wrong number of points in input file'
    allocate(displread(NDIM))
    allocate(velocread(NDIM))
    allocate(accelread(NDIM))
    do n = 1,npoin
      read(55,*) inump, (displread(i), i=1,NDIM), &
          (velocread(i), i=1,NDIM), (accelread(i), i=1,NDIM)
      if(inump<1 .or. inump>npoin) stop 'Wrong point number'
      displ_elastic(:,inump) = displread
      veloc_elastic(:,inump) = velocread
      accel_elastic(:,inump) = accelread
    enddo
    deallocate(displread)
    deallocate(velocread)
    deallocate(accelread)
    close(55)
    write(IOUT,*) 'Max norm of initial elastic displacement = ',maxval(sqrt(displ_elastic(1,:)**2 + displ_elastic(2,:)**2))
  endif

  deltatsquare = deltat * deltat
  deltatcube = deltatsquare * deltat
  deltatfourth = deltatsquare * deltatsquare

  twelvedeltat = 12.d0 * deltat
  fourdeltatsquare = 4.d0 * deltatsquare

! compute the source time function and store it in a text file
  if(.not. initialfield) then

    allocate(source_time_function(NSTEP))

    write(IOUT,*)
    write(IOUT,*) 'Saving the source time function in a text file...'
    write(IOUT,*)
    open(unit=55,file='OUTPUT_FILES/source.txt',status='unknown')

! loop on all the time steps
    do it = 1,NSTEP

! compute current time
      time = (it-1)*deltat

! Ricker (second derivative of a Gaussian) source time function
      if(time_function_type == 1) then
        source_time_function(it) = - factor * (ONE-TWO*a*(time-t0)**2) * exp(-a*(time-t0)**2)

! first derivative of a Gaussian source time function
      else if(time_function_type == 2) then
        source_time_function(it) = - factor * TWO*a*(time-t0) * exp(-a*(time-t0)**2)

! Gaussian or Dirac (we use a very thin Gaussian instead) source time function
      else if(time_function_type == 3 .or. time_function_type == 4) then
        source_time_function(it) = factor * exp(-a*(time-t0)**2)

! Heaviside source time function (we use a very thin error function instead)
      else if(time_function_type == 5) then
        hdur = 1.d0 / f0
        hdur_gauss = hdur * 5.d0 / 3.d0
        source_time_function(it) = factor * 0.5d0*(1.0d0+erf(SOURCE_DECAY_RATE*(time-t0)/hdur_gauss))

      else
        stop 'unknown source time function'
      endif

! output absolute time in third column, in case user wants to check it as well
      write(55,*) sngl(time),sngl(source_time_function(it)),sngl(time-t0)

    enddo

    close(55)

  else

    allocate(source_time_function(1))

  endif

!
!----  check that no element has both acoustic free surface and top absorbing surface
!
  do ispec_acoustic_surface = 1,nelem_acoustic_surface
    ispec = ispecnum_acoustic_surface(ispec_acoustic_surface)
    iedge = iedgenum_acoustic_surface(ispec_acoustic_surface)
    if(elastic(ispec)) then
      stop 'elastic element detected in acoustic free surface'
    else
      do inum = 1,nelemabs
        if(numabs(inum) == ispec .and. codeabs(iedge,inum)) &
          stop 'acoustic free surface cannot be both absorbing and free'
      enddo
    endif
  enddo

! determine if coupled fluid-solid simulation
  coupled_acoustic_elastic = any_acoustic .and. any_elastic

! fluid/solid edge detection
! very basic algorithm in O(nspec^2), simple double loop on the elements
! and then loop on the four corners of each of the two elements, could be signficantly improved

  num_fluid_solid_edges_alloc = 0

  if(coupled_acoustic_elastic) then
    print *
    print *,'Mixed acoustic/elastic simulation'
    print *
    print *,'Beginning of fluid/solid edge detection'

! define the edges of a given element
    i_begin(IBOTTOM) = 1
    j_begin(IBOTTOM) = 1
    i_end(IBOTTOM) = NGLLX
    j_end(IBOTTOM) = 1

    i_begin(IRIGHT) = NGLLX
    j_begin(IRIGHT) = 1
    i_end(IRIGHT) = NGLLX
    j_end(IRIGHT) = NGLLZ

    i_begin(ITOP) = NGLLX
    j_begin(ITOP) = NGLLZ
    i_end(ITOP) = 1
    j_end(ITOP) = NGLLZ

    i_begin(ILEFT) = 1
    j_begin(ILEFT) = NGLLZ
    i_end(ILEFT) = 1
    j_end(ILEFT) = 1

! define i and j points for each edge
    do ipoin1D = 1,NGLLX

      ivalue(ipoin1D,IBOTTOM) = ipoin1D
      ivalue_inverse(ipoin1D,IBOTTOM) = NGLLX - ipoin1D + 1
      jvalue(ipoin1D,IBOTTOM) = 1
      jvalue_inverse(ipoin1D,IBOTTOM) = 1

      ivalue(ipoin1D,IRIGHT) = NGLLX
      ivalue_inverse(ipoin1D,IRIGHT) = NGLLX
      jvalue(ipoin1D,IRIGHT) = ipoin1D
      jvalue_inverse(ipoin1D,IRIGHT) = NGLLZ - ipoin1D + 1

      ivalue(ipoin1D,ITOP) = NGLLX - ipoin1D + 1
      ivalue_inverse(ipoin1D,ITOP) = ipoin1D
      jvalue(ipoin1D,ITOP) = NGLLZ
      jvalue_inverse(ipoin1D,ITOP) = NGLLZ

      ivalue(ipoin1D,ILEFT) = 1
      ivalue_inverse(ipoin1D,ILEFT) = 1
      jvalue(ipoin1D,ILEFT) = NGLLZ - ipoin1D + 1
      jvalue_inverse(ipoin1D,ILEFT) = ipoin1D

    enddo

! double loop on all the elements
    do ispec_acoustic = 1, nspec
      do ispec_elastic = 1, nspec

! one element must be acoustic and the other must be elastic
! use acoustic element as master to avoid double detection of the same pair (one on each side)
        if(ispec_acoustic /= ispec_elastic .and. .not. elastic(ispec_acoustic) .and. elastic(ispec_elastic)) then

! loop on the four edges of the two elements
          do iedge_acoustic = 1,NEDGES
            do iedge_elastic = 1,NEDGES

! error if the two edges match in direct order
              if(ibool(i_begin(iedge_acoustic),j_begin(iedge_acoustic),ispec_acoustic) == &
                 ibool(i_begin(iedge_elastic),j_begin(iedge_elastic),ispec_elastic) .and. &
                 ibool(i_end(iedge_acoustic),j_end(iedge_acoustic),ispec_acoustic) == &
                 ibool(i_end(iedge_elastic),j_end(iedge_elastic),ispec_elastic)) &
                   stop 'topology error (non-inverted coupled elements) found in fluid/solid edge detection'

! the two edges can match in inverse order
              if(ibool(i_begin(iedge_acoustic),j_begin(iedge_acoustic),ispec_acoustic) == &
                 ibool(i_end(iedge_elastic),j_end(iedge_elastic),ispec_elastic) .and. &
                 ibool(i_end(iedge_acoustic),j_end(iedge_acoustic),ispec_acoustic) == &
                 ibool(i_begin(iedge_elastic),j_begin(iedge_elastic),ispec_elastic)) &
                   num_fluid_solid_edges_alloc = num_fluid_solid_edges_alloc + 1

            enddo
          enddo

        endif

      enddo
    enddo

    print *,'Number of fluid/solid edges detected in mesh = ',num_fluid_solid_edges_alloc

! allocate arrays for fluid/solid matching
    allocate(fluid_solid_acoustic_ispec(num_fluid_solid_edges_alloc))
    allocate(fluid_solid_acoustic_iedge(num_fluid_solid_edges_alloc))
    allocate(fluid_solid_elastic_ispec(num_fluid_solid_edges_alloc))
    allocate(fluid_solid_elastic_iedge(num_fluid_solid_edges_alloc))

! double loop on all the elements
    print *,'Creating fluid/solid edge topology...'

    num_fluid_solid_edges = 0

    do ispec_acoustic = 1, nspec
      do ispec_elastic = 1, nspec

! one element must be acoustic and the other must be elastic
! use acoustic element as master to avoid double detection of the same pair (one on each side)
        if(ispec_acoustic /= ispec_elastic .and. .not. elastic(ispec_acoustic) .and. elastic(ispec_elastic)) then

! loop on the four edges of the two elements
          do iedge_acoustic = 1,NEDGES
            do iedge_elastic = 1,NEDGES

! store the matching topology if the two edges match in inverse order
              if(ibool(i_begin(iedge_acoustic),j_begin(iedge_acoustic),ispec_acoustic) == &
                 ibool(i_end(iedge_elastic),j_end(iedge_elastic),ispec_elastic) .and. &
                 ibool(i_end(iedge_acoustic),j_end(iedge_acoustic),ispec_acoustic) == &
                 ibool(i_begin(iedge_elastic),j_begin(iedge_elastic),ispec_elastic)) then
                   num_fluid_solid_edges = num_fluid_solid_edges + 1
                   fluid_solid_acoustic_ispec(num_fluid_solid_edges) = ispec_acoustic
                   fluid_solid_acoustic_iedge(num_fluid_solid_edges) = iedge_acoustic
                   fluid_solid_elastic_ispec(num_fluid_solid_edges) = ispec_elastic
                   fluid_solid_elastic_iedge(num_fluid_solid_edges) = iedge_elastic
!                  print *,'edge ',iedge_acoustic,' of acoustic element ',ispec_acoustic, &
!                          ' is in contact with edge ',iedge_elastic,' of elastic element ',ispec_elastic
              endif

            enddo
          enddo

        endif

      enddo
    enddo

    if(num_fluid_solid_edges /= num_fluid_solid_edges_alloc) stop 'error in creation of arrays for fluid/solid matching'

! make sure fluid/solid matching has been perfectly detected: check that the grid points
! have the same physical coordinates
! loop on all the coupling edges

    print *,'Checking fluid/solid edge topology...'

    do inum = 1,num_fluid_solid_edges

! get the edge of the acoustic element
      ispec_acoustic = fluid_solid_acoustic_ispec(inum)
      iedge_acoustic = fluid_solid_acoustic_iedge(inum)

! get the corresponding edge of the elastic element
      ispec_elastic = fluid_solid_elastic_ispec(inum)
      iedge_elastic = fluid_solid_elastic_iedge(inum)

! implement 1D coupling along the edge
      do ipoin1D = 1,NGLLX

! get point values for the elastic side, which matches our side in the inverse direction
        i = ivalue_inverse(ipoin1D,iedge_elastic)
        j = jvalue_inverse(ipoin1D,iedge_elastic)
        iglob = ibool(i,j,ispec_elastic)

! get point values for the acoustic side
        i = ivalue(ipoin1D,iedge_acoustic)
        j = jvalue(ipoin1D,iedge_acoustic)
        iglob2 = ibool(i,j,ispec_acoustic)

! if distance between the two points is not negligible, there is an error, since it should be zero
        if(sqrt((coord(1,iglob) - coord(1,iglob2))**2 + (coord(2,iglob) - coord(2,iglob2))**2) > TINYVAL) &
            stop 'error in fluid/solid coupling buffer'

      enddo

    enddo

    print *,'End of fluid/solid edge detection'
    print *

  else

! allocate dummy arrays for fluid/solid matching if purely acoustic or purely elastic
    allocate(fluid_solid_acoustic_ispec(1))
    allocate(fluid_solid_acoustic_iedge(1))
    allocate(fluid_solid_elastic_ispec(1))
    allocate(fluid_solid_elastic_iedge(1))

  endif

! default values for acoustic absorbing edges
  ibegin_bottom(:) = 1
  ibegin_top(:) = 1

  iend_bottom(:) = NGLLX
  iend_top(:) = NGLLX

  jbegin_left(:) = 1
  jbegin_right(:) = 1

  jend_left(:) = NGLLZ
  jend_right(:) = NGLLZ

! exclude common points between acoustic absorbing edges and acoustic/elastic matching interface
  if(coupled_acoustic_elastic .and. anyabs) then

    print *,'excluding common points between acoustic absorbing edges and acoustic/elastic matching interface, if any'

    do ispecabs = 1,nelemabs

      ispec = numabs(ispecabs)

! loop on all the coupling edges
      do inum = 1,num_fluid_solid_edges

! get the edge of the acoustic element
        ispec_acoustic = fluid_solid_acoustic_ispec(inum)
        iedge_acoustic = fluid_solid_acoustic_iedge(inum)

! if acoustic absorbing element and acoustic/elastic coupled element is the same
        if(ispec_acoustic == ispec) then

          if(iedge_acoustic == IBOTTOM) then
            jbegin_left(ispecabs) = 2
            jbegin_right(ispecabs) = 2
          endif

          if(iedge_acoustic == ITOP) then
            jend_left(ispecabs) = NGLLZ - 1
            jend_right(ispecabs) = NGLLZ - 1
          endif

          if(iedge_acoustic == ILEFT) then
            ibegin_bottom(ispecabs) = 2
            ibegin_top(ispecabs) = 2
          endif

          if(iedge_acoustic == IRIGHT) then
            iend_bottom(ispecabs) = NGLLX - 1
            iend_top(ispecabs) = NGLLX - 1
          endif

        endif

      enddo

    enddo

  endif

!
!----          s t a r t   t i m e   i t e r a t i o n s
!

  write(IOUT,400)

! count elapsed wall-clock time
  datein = ''
  timein = ''
  zone = ''

  call date_and_time(datein,timein,zone,time_values)
! time_values(3): day of the month
! time_values(5): hour of the day
! time_values(6): minutes of the hour
! time_values(7): seconds of the minute
! time_values(8): milliseconds of the second
! this fails if we cross the end of the month
  time_start = 86400.d0*time_values(3) + 3600.d0*time_values(5) + &
               60.d0*time_values(6) + time_values(7) + time_values(8) / 1000.d0

! *********************************************************
! ************* MAIN LOOP OVER THE TIME STEPS *************
! *********************************************************

  do it = 1,NSTEP

! compute current time
    time = (it-1)*deltat

! update displacement using finite-difference time scheme (Newmark)
    if(any_elastic) then
      displ_elastic = displ_elastic + deltat*veloc_elastic + deltatsquareover2*accel_elastic
      veloc_elastic = veloc_elastic + deltatover2*accel_elastic
      accel_elastic = ZERO
    endif

    if(any_acoustic) then

      potential_acoustic = potential_acoustic + deltat*potential_dot_acoustic + deltatsquareover2*potential_dot_dot_acoustic
      potential_dot_acoustic = potential_dot_acoustic + deltatover2*potential_dot_dot_acoustic
      potential_dot_dot_acoustic = ZERO

! free surface for an acoustic medium
    call enforce_acoustic_free_surface(potential_dot_dot_acoustic,potential_dot_acoustic, &
                potential_acoustic,ispecnum_acoustic_surface,iedgenum_acoustic_surface, &
                ibool,nelem_acoustic_surface,npoin,nspec)

! *********************************************************
! ************* compute forces for the acoustic elements
! *********************************************************

    call compute_forces_acoustic(npoin,nspec,nelemabs,numat, &
               iglob_source,ispec_selected_source,source_type,it,NSTEP,anyabs, &
               assign_external_model,initialfield,ibool,kmato,numabs, &
               elastic,codeabs,potential_dot_dot_acoustic,potential_dot_acoustic, &
               potential_acoustic,density,elastcoef,xix,xiz,gammax,gammaz,jacobian, &
               vpext,vsext,rhoext,source_time_function,hprime_xx,hprimewgll_xx, &
               hprime_zz,hprimewgll_zz,wxgll,wzgll, &
               ibegin_bottom,iend_bottom,ibegin_top,iend_top, &
               jbegin_left,jend_left,jbegin_right,jend_right)

    endif ! end of test if any acoustic element

! *********************************************************
! ************* add coupling with the elastic side
! *********************************************************

    if(coupled_acoustic_elastic) then

! loop on all the coupling edges
      do inum = 1,num_fluid_solid_edges

! get the edge of the acoustic element
        ispec_acoustic = fluid_solid_acoustic_ispec(inum)
        iedge_acoustic = fluid_solid_acoustic_iedge(inum)

! get the corresponding edge of the elastic element
        ispec_elastic = fluid_solid_elastic_ispec(inum)
        iedge_elastic = fluid_solid_elastic_iedge(inum)

! implement 1D coupling along the edge
        do ipoin1D = 1,NGLLX

! get point values for the elastic side, which matches our side in the inverse direction
          i = ivalue_inverse(ipoin1D,iedge_elastic)
          j = jvalue_inverse(ipoin1D,iedge_elastic)
          iglob = ibool(i,j,ispec_elastic)

          displ_x = displ_elastic(1,iglob)
          displ_z = displ_elastic(2,iglob)

! get point values for the acoustic side
          i = ivalue(ipoin1D,iedge_acoustic)
          j = jvalue(ipoin1D,iedge_acoustic)
          iglob = ibool(i,j,ispec_acoustic)

! compute the 1D Jacobian and the normal to the edge: for their expression see for instance
! O. C. Zienkiewicz and R. L. Taylor, The Finite Element Method for Solid and Structural Mechanics,
! Sixth Edition, electronic version, www.amazon.com, p. 204 and Figure 7.7(a),
! or Y. K. Cheung, S. H. Lo and A. Y. T. Leung, Finite Element Implementation,
! Blackwell Science, page 110, equation (4.60).
          if(iedge_acoustic == IBOTTOM .or. iedge_acoustic == ITOP) then
            xxi = + gammaz(i,j,ispec_acoustic) * jacobian(i,j,ispec_acoustic)
            zxi = - gammax(i,j,ispec_acoustic) * jacobian(i,j,ispec_acoustic)
            jacobian1D = sqrt(xxi**2 + zxi**2)
            nx = + zxi / jacobian1D
            nz = - xxi / jacobian1D
          else
            xgamma = - xiz(i,j,ispec_acoustic) * jacobian(i,j,ispec_acoustic)
            zgamma = + xix(i,j,ispec_acoustic) * jacobian(i,j,ispec_acoustic)
            jacobian1D = sqrt(xgamma**2 + zgamma**2)
            nx = + zgamma / jacobian1D
            nz = - xgamma / jacobian1D
          endif

! compute dot product
          displ_n = displ_x*nx + displ_z*nz

! formulation with generalized potential
          weight = jacobian1D * wxgll(i)

          potential_dot_dot_acoustic(iglob) = potential_dot_dot_acoustic(iglob) + weight*displ_n

        enddo

      enddo

    endif

! ************************************************************************************
! ************* multiply by the inverse of the mass matrix and update velocity
! ************************************************************************************

  if(any_acoustic) then

    potential_dot_dot_acoustic = potential_dot_dot_acoustic * rmass_inverse_acoustic
    potential_dot_acoustic = potential_dot_acoustic + deltatover2*potential_dot_dot_acoustic

! free surface for an acoustic medium
    call enforce_acoustic_free_surface(potential_dot_dot_acoustic,potential_dot_acoustic, &
                potential_acoustic,ispecnum_acoustic_surface,iedgenum_acoustic_surface, &
                ibool,nelem_acoustic_surface,npoin,nspec)
  endif

! *********************************************************
! ************* main solver for the elastic elements
! *********************************************************

  if(any_elastic) &
    call compute_forces_elastic(npoin,nspec,nelemabs,numat,iglob_source, &
               ispec_selected_source,source_type,it,NSTEP,anyabs,assign_external_model, &
               initialfield,TURN_ATTENUATION_ON,TURN_ANISOTROPY_ON,angleforce,deltatcube, &
               deltatfourth,twelvedeltat,fourdeltatsquare,ibool,kmato,numabs,elastic,codeabs, &
               accel_elastic,veloc_elastic,displ_elastic,density,elastcoef,xix,xiz,gammax,gammaz, &
               jacobian,vpext,vsext,rhoext,source_time_function,sourcearray,e1_mech1,e11_mech1, &
               e13_mech1,e1_mech2,e11_mech2,e13_mech2,dux_dxl_n,duz_dzl_n,duz_dxl_n,dux_dzl_n, &
               dux_dxl_np1,duz_dzl_np1,duz_dxl_np1,dux_dzl_np1,hprime_xx,hprimewgll_xx, &
               hprime_zz,hprimewgll_zz,wxgll,wzgll)

! *********************************************************
! ************* add coupling with the acoustic side
! *********************************************************

    if(coupled_acoustic_elastic) then

! loop on all the coupling edges
      do inum = 1,num_fluid_solid_edges

! get the edge of the acoustic element
        ispec_acoustic = fluid_solid_acoustic_ispec(inum)
        iedge_acoustic = fluid_solid_acoustic_iedge(inum)

! get the corresponding edge of the elastic element
        ispec_elastic = fluid_solid_elastic_ispec(inum)
        iedge_elastic = fluid_solid_elastic_iedge(inum)

! implement 1D coupling along the edge
        do ipoin1D = 1,NGLLX

! get point values for the acoustic side, which matches our side in the inverse direction
          i = ivalue_inverse(ipoin1D,iedge_acoustic)
          j = jvalue_inverse(ipoin1D,iedge_acoustic)
          iglob = ibool(i,j,ispec_acoustic)

! get density of the fluid, depending if external density model
          if(assign_external_model) then
            rhol = rhoext(i,j,ispec_acoustic)
          else
            rhol = density(kmato(ispec_acoustic))
          endif

! compute pressure on the fluid/solid edge
          pressure = - rhol * potential_dot_dot_acoustic(iglob)

! get point values for the elastic side
          i = ivalue(ipoin1D,iedge_elastic)
          j = jvalue(ipoin1D,iedge_elastic)
          iglob = ibool(i,j,ispec_elastic)

! compute the 1D Jacobian and the normal to the edge: for their expression see for instance
! O. C. Zienkiewicz and R. L. Taylor, The Finite Element Method for Solid and Structural Mechanics,
! Sixth Edition, electronic version, www.amazon.com, p. 204 and Figure 7.7(a),
! or Y. K. Cheung, S. H. Lo and A. Y. T. Leung, Finite Element Implementation,
! Blackwell Science, page 110, equation (4.60).
          if(iedge_acoustic == IBOTTOM .or. iedge_acoustic == ITOP) then
            xxi = + gammaz(i,j,ispec_acoustic) * jacobian(i,j,ispec_acoustic)
            zxi = - gammax(i,j,ispec_acoustic) * jacobian(i,j,ispec_acoustic)
            jacobian1D = sqrt(xxi**2 + zxi**2)
            nx = + zxi / jacobian1D
            nz = - xxi / jacobian1D
          else
            xgamma = - xiz(i,j,ispec_acoustic) * jacobian(i,j,ispec_acoustic)
            zgamma = + xix(i,j,ispec_acoustic) * jacobian(i,j,ispec_acoustic)
            jacobian1D = sqrt(xgamma**2 + zgamma**2)
            nx = + zgamma / jacobian1D
            nz = - xgamma / jacobian1D
          endif

! formulation with generalized potential
          weight = jacobian1D * wxgll(i)

          accel_elastic(1,iglob) = accel_elastic(1,iglob) + weight*nx*pressure
          accel_elastic(2,iglob) = accel_elastic(2,iglob) + weight*nz*pressure

        enddo

      enddo

    endif

! ************************************************************************************
! ************* multiply by the inverse of the mass matrix and update velocity
! ************************************************************************************

  if(any_elastic) then
    accel_elastic(1,:) = accel_elastic(1,:) * rmass_inverse_elastic
    accel_elastic(2,:) = accel_elastic(2,:) * rmass_inverse_elastic
    veloc_elastic = veloc_elastic + deltatover2*accel_elastic
  endif

!----  display time step and max of norm of displacement
  if(mod(it,NTSTEP_BETWEEN_OUTPUT_INFO) == 0 .or. it == 5) then

    write(IOUT,*)
    if(time >= 1.d-3 .and. time < 1000.d0) then
      write(IOUT,"('Time step number ',i6,'   t = ',f9.4,' s')") it,time
    else
      write(IOUT,"('Time step number ',i6,'   t = ',1pe12.6,' s')") it,time
    endif

    if(any_elastic) then
      displnorm_all = maxval(sqrt(displ_elastic(1,:)**2 + displ_elastic(2,:)**2))
      write(IOUT,*) 'Max norm of vector field in solid = ',displnorm_all
! check stability of the code in solid, exit if unstable
      if(displnorm_all > STABILITY_THRESHOLD) stop 'code became unstable and blew up in solid'
    endif

    if(any_acoustic) then
      displnorm_all = maxval(abs(potential_acoustic(:)))
      write(IOUT,*) 'Max absolute value of scalar field in fluid = ',displnorm_all
! check stability of the code in fluid, exit if unstable
      if(displnorm_all > STABILITY_THRESHOLD) stop 'code became unstable and blew up in fluid'
    endif

    write(IOUT,*)
  endif

! loop on all the receivers to compute and store the seismograms
  do irec = 1,nrec

    ispec = ispec_selected_rec(irec)

! compute pressure in this element if needed
    if(seismotype == 4) then

      call compute_pressure_one_element(pressure_element,potential_dot_dot_acoustic,displ_elastic,elastic, &
            xix,xiz,gammax,gammaz,ibool,hprime_xx,hprime_zz,nspec,npoin,assign_external_model, &
            numat,kmato,density,elastcoef,vpext,vsext,rhoext,ispec,e1_mech1,e11_mech1, &
            e1_mech2,e11_mech2,TURN_ATTENUATION_ON,TURN_ANISOTROPY_ON)

    else if(.not. elastic(ispec)) then

! for acoustic medium, compute vector field from gradient of potential for seismograms
      if(seismotype == 1) then
        call compute_vector_one_element(vector_field_element,potential_acoustic,displ_elastic,elastic, &
               xix,xiz,gammax,gammaz,ibool,hprime_xx,hprime_zz,nspec,npoin,ispec)
      else if(seismotype == 2) then
        call compute_vector_one_element(vector_field_element,potential_dot_acoustic,veloc_elastic,elastic, &
               xix,xiz,gammax,gammaz,ibool,hprime_xx,hprime_zz,nspec,npoin,ispec)
      else if(seismotype == 3) then
        call compute_vector_one_element(vector_field_element,potential_dot_dot_acoustic,accel_elastic,elastic, &
               xix,xiz,gammax,gammaz,ibool,hprime_xx,hprime_zz,nspec,npoin,ispec)
      endif

    endif

! perform the general interpolation using Lagrange polynomials
    valux = ZERO
    valuz = ZERO

    do j = 1,NGLLZ
      do i = 1,NGLLX

        iglob = ibool(i,j,ispec)

        hlagrange = hxir_store(irec,i)*hgammar_store(irec,j)

        if(seismotype == 4) then

          dxd = pressure_element(i,j)
          dzd = ZERO

        else if(.not. elastic(ispec)) then

          dxd = vector_field_element(1,i,j)
          dzd = vector_field_element(2,i,j)

        else if(seismotype == 1) then

          dxd = displ_elastic(1,iglob)
          dzd = displ_elastic(2,iglob)

        else if(seismotype == 2) then

          dxd = veloc_elastic(1,iglob)
          dzd = veloc_elastic(2,iglob)

        else if(seismotype == 3) then

          dxd = accel_elastic(1,iglob)
          dzd = accel_elastic(2,iglob)

        endif

! compute interpolated field
        valux = valux + dxd*hlagrange
        valuz = valuz + dzd*hlagrange

      enddo
    enddo

! rotate seismogram components if needed, except if recording pressure, which is a scalar
    if(seismotype /= 4) then
      sisux(it,irec) =   cosrot*valux + sinrot*valuz
      sisuz(it,irec) = - sinrot*valux + cosrot*valuz
    else
      sisux(it,irec) = valux
      sisuz(it,irec) = ZERO
    endif

  enddo

!
!----  display results at given time steps
!
  if(mod(it,NTSTEP_BETWEEN_OUTPUT_INFO) == 0 .or. it == 5 .or. it == NSTEP) then

!
!----  PostScript display
!
  if(output_postscript_snapshot) then

  write(IOUT,*) 'Writing PostScript file'

  if(imagetype == 1) then

    write(IOUT,*) 'drawing displacement vector as small arrows...'

    call compute_vector_whole_medium(potential_acoustic,displ_elastic,elastic,vector_field_display, &
          xix,xiz,gammax,gammaz,ibool,hprime_xx,hprime_zz,nspec,npoin)

    call plotpost(vector_field_display,coord,vpext,x_source,z_source,st_xval,st_zval, &
          it,deltat,coorg,xinterp,zinterp,shape2D_display, &
          Uxinterp,Uzinterp,flagrange,density,elastcoef,knods,kmato,ibool, &
          numabs,codeabs,anyabs,simulation_title,npoin,npgeo,vpmin,vpmax,nrec, &
          colors,numbers,subsamp,imagetype,interpol,meshvect,modelvect, &
          boundvect,assign_external_model,cutsnaps,sizemax_arrows,nelemabs,numat,pointsdisp, &
          nspec,ngnod,coupled_acoustic_elastic,any_acoustic,plot_lowerleft_corner_only, &
          fluid_solid_acoustic_ispec,fluid_solid_acoustic_iedge,num_fluid_solid_edges)

  else if(imagetype == 2) then

    write(IOUT,*) 'drawing velocity vector as small arrows...'

    call compute_vector_whole_medium(potential_dot_acoustic,veloc_elastic,elastic,vector_field_display, &
          xix,xiz,gammax,gammaz,ibool,hprime_xx,hprime_zz,nspec,npoin)

    call plotpost(vector_field_display,coord,vpext,x_source,z_source,st_xval,st_zval, &
          it,deltat,coorg,xinterp,zinterp,shape2D_display, &
          Uxinterp,Uzinterp,flagrange,density,elastcoef,knods,kmato,ibool, &
          numabs,codeabs,anyabs,simulation_title,npoin,npgeo,vpmin,vpmax,nrec, &
          colors,numbers,subsamp,imagetype,interpol,meshvect,modelvect, &
          boundvect,assign_external_model,cutsnaps,sizemax_arrows,nelemabs,numat,pointsdisp, &
          nspec,ngnod,coupled_acoustic_elastic,any_acoustic,plot_lowerleft_corner_only, &
          fluid_solid_acoustic_ispec,fluid_solid_acoustic_iedge,num_fluid_solid_edges)

  else if(imagetype == 3) then

    write(IOUT,*) 'drawing acceleration vector as small arrows...'

    call compute_vector_whole_medium(potential_dot_dot_acoustic,accel_elastic,elastic,vector_field_display, &
          xix,xiz,gammax,gammaz,ibool,hprime_xx,hprime_zz,nspec,npoin)

    call plotpost(vector_field_display,coord,vpext,x_source,z_source,st_xval,st_zval, &
          it,deltat,coorg,xinterp,zinterp,shape2D_display, &
          Uxinterp,Uzinterp,flagrange,density,elastcoef,knods,kmato,ibool, &
          numabs,codeabs,anyabs,simulation_title,npoin,npgeo,vpmin,vpmax,nrec, &
          colors,numbers,subsamp,imagetype,interpol,meshvect,modelvect, &
          boundvect,assign_external_model,cutsnaps,sizemax_arrows,nelemabs,numat,pointsdisp, &
          nspec,ngnod,coupled_acoustic_elastic,any_acoustic,plot_lowerleft_corner_only, &
          fluid_solid_acoustic_ispec,fluid_solid_acoustic_iedge,num_fluid_solid_edges)

  else if(imagetype == 4) then

    write(IOUT,*) 'cannot draw scalar pressure field as a vector plot, skipping...'

  else
    stop 'wrong type for snapshots'
  endif

  if(imagetype /= 4) write(IOUT,*) 'PostScript file written'

  endif

!
!----  display color image
!
  if(output_color_image) then

  write(IOUT,*) 'Creating color image of size ',NX_IMAGE_color,' x ',NZ_IMAGE_color

  if(imagetype == 1) then

    write(IOUT,*) 'drawing image of vertical component of displacement vector...'

    call compute_vector_whole_medium(potential_acoustic,displ_elastic,elastic,vector_field_display, &
          xix,xiz,gammax,gammaz,ibool,hprime_xx,hprime_zz,nspec,npoin)

  else if(imagetype == 2) then

    write(IOUT,*) 'drawing image of vertical component of velocity vector...'

    call compute_vector_whole_medium(potential_dot_acoustic,veloc_elastic,elastic,vector_field_display, &
          xix,xiz,gammax,gammaz,ibool,hprime_xx,hprime_zz,nspec,npoin)

  else if(imagetype == 3) then

    write(IOUT,*) 'drawing image of vertical component of acceleration vector...'

    call compute_vector_whole_medium(potential_dot_dot_acoustic,accel_elastic,elastic,vector_field_display, &
          xix,xiz,gammax,gammaz,ibool,hprime_xx,hprime_zz,nspec,npoin)

  else if(imagetype == 4) then

    write(IOUT,*) 'drawing image of pressure field...'

    call compute_pressure_whole_medium(potential_dot_dot_acoustic,displ_elastic,elastic,vector_field_display, &
         xix,xiz,gammax,gammaz,ibool,hprime_xx,hprime_zz,nspec,npoin,assign_external_model, &
         numat,kmato,density,elastcoef,vpext,vsext,rhoext,e1_mech1,e11_mech1, &
         e1_mech2,e11_mech2,TURN_ATTENUATION_ON,TURN_ANISOTROPY_ON)

  else
    stop 'wrong type for snapshots'
  endif

  image_color_data(:,:) = 0.d0
  do j = 1,NZ_IMAGE_color
    do i = 1,NX_IMAGE_color
      iglob = iglob_image_color(i,j)
! draw vertical component of field
! or pressure which is stored in the same array used as temporary storage
      if(iglob /= -1) image_color_data(i,j) = vector_field_display(2,iglob)
    enddo
  enddo

  call create_color_image(image_color_data,iglob_image_color,NX_IMAGE_color,NZ_IMAGE_color,it,cutsnaps)

  write(IOUT,*) 'Color image created'

  endif

!----  save temporary or final seismograms
  call write_seismograms(sisux,sisuz,station_name,network_name,NSTEP, &
         nrec,deltat,seismotype,st_xval,it,t0,buffer_binary_single,buffer_binary_double)

! count elapsed wall-clock time
  call date_and_time(datein,timein,zone,time_values)
! time_values(3): day of the month
! time_values(5): hour of the day
! time_values(6): minutes of the hour
! time_values(7): seconds of the minute
! time_values(8): milliseconds of the second
! this fails if we cross the end of the month
  time_end = 86400.d0*time_values(3) + 3600.d0*time_values(5) + &
             60.d0*time_values(6) + time_values(7) + time_values(8) / 1000.d0

! elapsed time since beginning of the simulation
  tCPU = time_end - time_start
  int_tCPU = int(tCPU)
  ihours = int_tCPU / 3600
  iminutes = (int_tCPU - 3600*ihours) / 60
  iseconds = int_tCPU - 3600*ihours - 60*iminutes
  write(*,*) 'Elapsed time in seconds = ',tCPU
  write(*,"(' Elapsed time in hh:mm:ss = ',i4,' h ',i2.2,' m ',i2.2,' s')") ihours,iminutes,iseconds
  write(*,*) 'Mean elapsed time per time step in seconds = ',tCPU/dble(it)
  write(*,*)

  endif

  enddo ! end of the main time loop

! print exit banner
  call datim(simulation_title)

!
!----  close output file
!
  if(IOUT /= ISTANDARD_OUTPUT) close(IOUT)

!
!----  formats
!

 400 format(/1x,41('=')/,' =  T i m e  e v o l u t i o n  l o o p  ='/1x,41('=')/)

 200 format(//1x,'C o n t r o l',/1x,13('='),//5x,&
  'Number of spectral element control nodes. . .(npgeo) =',i8/5x, &
  'Number of space dimensions. . . . . . . . . . (NDIM) =',i8)

 600 format(//1x,'C o n t r o l',/1x,13('='),//5x, &
  'Display frequency . . . (NTSTEP_BETWEEN_OUTPUT_INFO) = ',i6/ 5x, &
  'Color display . . . . . . . . . . . . . . . (colors) = ',i6/ 5x, &
  '        ==  0     black and white display              ',  / 5x, &
  '        ==  1     color display                        ',  /5x, &
  'Numbered mesh . . . . . . . . . . . . . . .(numbers) = ',i6/ 5x, &
  '        ==  0     do not number the mesh               ',  /5x, &
  '        ==  1     number the mesh                      ')

 700 format(//1x,'C o n t r o l',/1x,13('='),//5x, &
  'Seismograms recording type . . . . . . .(seismotype) = ',i6/5x, &
  'Angle for first line of receivers. . . . .(anglerec) = ',f6.2)

 750 format(//1x,'C o n t r o l',/1x,13('='),//5x, &
  'Read external initial field. . . . . .(initialfield) = ',l6/5x, &
  'Assign external model . . . .(assign_external_model) = ',l6/5x, &
  'Turn anisotropy on or off. . . .(TURN_ANISOTROPY_ON) = ',l6/5x, &
  'Turn attenuation on or off. . .(TURN_ATTENUATION_ON) = ',l6/5x, &
  'Save grid in external file or not. . . .(outputgrid) = ',l6)

 800 format(//1x,'C o n t r o l',/1x,13('='),//5x, &
  'Vector display type . . . . . . . . . . .(imagetype) = ',i6/5x, &
  'Percentage of cut for vector plots . . . .(cutsnaps) = ',f6.2/5x, &
  'Subsampling for velocity model display. . .(subsamp) = ',i6)

 703 format(//' I t e r a t i o n s '/1x,19('='),//5x, &
      'Number of time iterations . . . . .(NSTEP) =',i8,/5x, &
      'Time step increment. . . . . . . .(deltat) =',1pe15.6,/5x, &
      'Total simulation duration . . . . . (ttot) =',1pe15.6)

 107 format(/5x,'--> Isoparametric Spectral Elements <--',//)

 207 format(5x,'Number of spectral elements . . . . .  (nspec) =',i7,/5x, &
               'Number of control nodes per element .  (ngnod) =',i7,/5x, &
               'Number of points in X-direction . . .  (NGLLX) =',i7,/5x, &
               'Number of points in Y-direction . . .  (NGLLZ) =',i7,/5x, &
               'Number of points per element. . .(NGLLX*NGLLZ) =',i7,/5x, &
               'Number of points for display . . .(pointsdisp) =',i7,/5x, &
               'Number of element material sets . . .  (numat) =',i7,/5x, &
               'Number of absorbing elements . . . .(nelemabs) =',i7)

 212 format(//,5x,'Source Type. . . . . . . . . . . . . . = Collocated Force',/5x, &
                  'X-position (meters). . . . . . . . . . =',1pe20.10,/5x, &
                  'Y-position (meters). . . . . . . . . . =',1pe20.10,/5x, &
                  'Fundamental frequency (Hz) . . . . . . =',1pe20.10,/5x, &
                  'Time delay (s) . . . . . . . . . . . . =',1pe20.10,/5x, &
                  'Multiplying factor . . . . . . . . . . =',1pe20.10,/5x, &
                  'Angle from vertical direction (deg). . =',1pe20.10,/5x)

 222 format(//,5x,'Source Type. . . . . . . . . . . . . . = Moment-tensor',/5x, &
                  'X-position (meters). . . . . . . . . . =',1pe20.10,/5x, &
                  'Y-position (meters). . . . . . . . . . =',1pe20.10,/5x, &
                  'Fundamental frequency (Hz) . . . . . . =',1pe20.10,/5x, &
                  'Time delay (s) . . . . . . . . . . . . =',1pe20.10,/5x, &
                  'Multiplying factor . . . . . . . . . . =',1pe20.10,/5x, &
                  'Mxx. . . . . . . . . . . . . . . . . . =',1pe20.10,/5x, &
                  'Mzz. . . . . . . . . . . . . . . . . . =',1pe20.10,/5x, &
                  'Mxz. . . . . . . . . . . . . . . . . . =',1pe20.10)

  end program specfem2D

