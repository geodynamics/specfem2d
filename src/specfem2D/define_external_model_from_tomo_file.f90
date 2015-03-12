
!========================================================================
!
!                   S P E C F E M 2 D  Version 7 . 0
!                   --------------------------------
!
!     Main historical authors: Dimitri Komatitsch and Jeroen Tromp
!                        Princeton University, USA
!                and CNRS / University of Marseille, France
!                 (there are currently many more authors!)
! (c) Princeton University and CNRS / University of Marseille, April 2014
!
! This software is a computer program whose purpose is to solve
! the two-dimensional viscoelastic anisotropic or poroelastic wave equation
! using a spectral-element method (SEM).
!
! This software is governed by the CeCILL license under French law and
! abiding by the rules of distribution of free software. You can use,
! modify and/or redistribute the software under the terms of the CeCILL
! license as circulated by CEA, CNRS and Inria at the following URL
! "http://www.cecill.info".
!
! As a counterpart to the access to the source code and rights to copy,
! modify and redistribute granted by the license, users are provided only
! with a limited warranty and the software's author, the holder of the
! economic rights, and the successive licensors have only limited
! liability.
!
! In this respect, the user's attention is drawn to the risks associated
! with loading, using, modifying and/or developing or reproducing the
! software by the user in light of its specific status of free software,
! that may mean that it is complicated to manipulate, and that also
! therefore means that it is reserved for developers and experienced
! professionals having in-depth computer knowledge. Users are therefore
! encouraged to load and test the software's suitability as regards their
! requirements in conditions enabling the security of their systems and/or
! data to be ensured and, more generally, to use and operate it in the
! same conditions as regards security.
!
! The full text of the license is available in file "LICENSE".
!
!========================================================================

module model_tomography_par
! ----------------------------------------------------------------------------------------
! Contains the variables needed to read an ASCII tomo file
! ----------------------------------------------------------------------------------------

  use constants,only: CUSTOM_REAL

  implicit none

  ! for external tomography:
  ! (regular spaced, xyz-block file in ascii)

  ! models dimensions
  double precision  :: END_X,END_Z

  double precision :: ORIGIN_X,ORIGIN_Z
  double precision :: SPACING_X,SPACING_Z

  ! models parameter records
  real(kind=CUSTOM_REAL), dimension(:), allocatable :: x_tomo,z_tomo
  real(kind=CUSTOM_REAL), dimension(:,:), allocatable :: vp_tomo,vs_tomo,rho_tomo

  ! models entries
  integer :: NX,NZ
  integer :: nrecord

  ! min/max statistics
  double precision :: VP_MIN,VS_MIN,RHO_MIN,VP_MAX,VS_MAX,RHO_MAX

end module model_tomography_par

!
! ----------------------------------------------------------------------------------------
!

subroutine define_external_model_from_tomo_file()
! ----------------------------------------------------------------------------------------
! Read a tomo file and loop over all GLL points to set the values of vp,vs and rho
! ----------------------------------------------------------------------------------------

  use specfem_par, only: tomo_material,coord,nspec,ibool,kmato,rhoext,vpext,vsext,gravityext, &
                       QKappa_attenuationext,Qmu_attenuationext,poroelastcoef,density, &
                       c11ext,c13ext,c15ext,c33ext,c35ext,c55ext,c12ext,c23ext,c25ext

  use model_tomography_par
  use interpolation

  use constants,only: NGLLX,NGLLZ,TINYVAL

  implicit none

  ! local parameters

  integer :: i,j,ispec,iglob
  double precision :: xmesh,zmesh

  call read_tomo_file() ! Read external tomo file TOMOGRAPHY_FILE

  ! loop on all the elements of the mesh, and inside each element loop on all the GLL points

  do ispec = 1,nspec
    do j = 1,NGLLZ
      do i = 1,NGLLX
         iglob = ibool(i,j,ispec)
         if (kmato(ispec) == tomo_material) then ! If the material has been set to <0 on the Par_file
           xmesh = coord(1,iglob)
           zmesh = coord(2,iglob)
           rhoext(i,j,ispec) = interpolate(NX, x_tomo, NZ, z_tomo, rho_tomo, xmesh, zmesh,TINYVAL)
           vpext(i,j,ispec) = interpolate(NX, x_tomo, NZ, z_tomo, vp_tomo, xmesh, zmesh,TINYVAL)
           vsext(i,j,ispec) = interpolate(NX, x_tomo, NZ, z_tomo, vs_tomo, xmesh, zmesh,TINYVAL)
           QKappa_attenuationext(i,j,ispec) = 9999. ! this means no attenuation
           Qmu_attenuationext(i,j,ispec)    = 9999. ! this means no attenuation
           c11ext(i,j,ispec) = 0.d0   ! this means no anisotropy
           c13ext(i,j,ispec) = 0.d0
           c15ext(i,j,ispec) = 0.d0
           c33ext(i,j,ispec) = 0.d0
           c35ext(i,j,ispec) = 0.d0
           c55ext(i,j,ispec) = 0.d0
           c12ext(i,j,ispec) = 0.d0
           c23ext(i,j,ispec) = 0.d0
           c25ext(i,j,ispec) = 0.d0
         else
           rhoext(i,j,ispec) = density(1,kmato(ispec))
           vpext(i,j,ispec) = sqrt(poroelastcoef(3,1,kmato(ispec))/rhoext(i,j,ispec))
           vsext(i,j,ispec) = sqrt(poroelastcoef(2,1,kmato(ispec))/rhoext(i,j,ispec))
           QKappa_attenuationext(i,j,ispec) = 9999. ! this means no attenuation
           Qmu_attenuationext(i,j,ispec)    = 9999. ! this means no attenuation
           c11ext(i,j,ispec) = 0.d0   ! this means no anisotropy
           c13ext(i,j,ispec) = 0.d0
           c15ext(i,j,ispec) = 0.d0
           c33ext(i,j,ispec) = 0.d0
           c35ext(i,j,ispec) = 0.d0
           c55ext(i,j,ispec) = 0.d0
           c12ext(i,j,ispec) = 0.d0
           c23ext(i,j,ispec) = 0.d0
           c25ext(i,j,ispec) = 0.d0
         endif
      enddo
    enddo
  enddo

end subroutine define_external_model_from_tomo_file

!
!-------------------------------------------------------------------------------------------
!

subroutine read_tomo_file()
  ! ----------------------------------------------------------------------------------------
  ! This subroutine reads the external ASCII tomo file TOMOGRAPHY_FILE (path to which is
  ! given in the Par_file).
  ! This file format is not very clever however it is the one used in specfem3D hence
  ! we chose to implement it here as well
  ! The external tomographic model is represented by a grid of points with assigned material
  ! properties and homogeneous resolution along each spatial direction x and z. The xyz file
  ! TOMOGRAPHY_FILE that describe the tomography should be located in the TOMOGRAPHY_PATH
  ! directory, set in the Par_file. The format of the file, as read from
  ! define_external_model_from_xyz_file.f90 looks like :
  !
  ! ORIGIN_X ORIGIN_Z END_X END_Z
  ! SPACING_X SPACING_Z
  ! NX NZ
  ! VP_MIN VP_MAX VS_MIN VS_MAX RHO_MIN RHO_MAX
  ! x(1) z(0) vp vs rho
  ! x(2) z(0) vp vs rho
  ! ...
  ! x(NX) z(0) vp vs rho
  ! x(1) z(1) vp vs rho
  ! x(2) z(1) vp vs rho
  ! ...
  ! x(NX) z(1) vp vs rho
  ! x(1) z(2) vp vs rho
  ! ...
  ! ...
  ! x(NX) z(NZ) vp vs rho
  !
  ! Where :
  ! _ORIGIN_X, END_X are, respectively, the coordinates of the initial and final tomographic
  !  grid points along the x direction (in meters)
  ! _ORIGIN_Z, END_Z are, respectively, the coordinates of the initial and final tomographic
  !  grid points along the z direction (in meters)
  ! _SPACING_X, SPACING_Z are the spacing between the tomographic grid points along the x
  !  and z directions, respectively (in meters)
  ! _NX, NZ are the number of grid points along the spatial directions x and z,
  !  respectively; NX is given by [(END_X - ORIGIN_X)/SPACING_X]+1; NZ is the same as NX, but
  !  for z direction.
  ! _VP_MIN, VP_MAX, VS_MIN, VS_MAX, RHO_MIN, RHO_MAX are the minimum and maximum values of
  !  the wave speed vp and vs (in m.s-1) and of the density rho (in kg.m-3); these values
  !  could be the actual limits of the tomographic parameters in the grid or the minimum
  !  and maximum values to which we force the cut of velocity and density in the model.
  ! _After these first four lines, in the file file_name the tomographic grid points are
  !  listed with the corresponding values of vp, vs and rho, scanning the grid along the x
  !  coordinate (from ORIGIN_X to END_X with step of SPACING_X) for each given z (from ORIGIN_Z
  !  to END_Z, with step of SPACING_Z).
  ! ----------------------------------------------------------------------------------------

  use specfem_par, only: myrank,TOMOGRAPHY_FILE

  use model_tomography_par
  use constants,only: IIN,IOUT,CUSTOM_REAL

  implicit none

  ! local parameters

  integer :: ier,irecord,i,j
  character(len=150) :: string_read
  
  real(kind=CUSTOM_REAL), dimension(:), allocatable :: x_tomography,z_tomography,vp_tomography,vs_tomography,rho_tomography

  ! opens file for reading
  open(unit=IIN,file=trim(TOMOGRAPHY_FILE),status='old',action='read',iostat=ier)
  if (ier /= 0) then
    print *,'Error: could not open tomography file: ',trim(TOMOGRAPHY_FILE)
    print *,'Please check your settings in Par_file ...'
    call exit_MPI('Error reading tomography file')
  endif

  ! --------------------------------------------------------------------------------------
  ! header infos
  ! --------------------------------------------------------------------------------------
  ! reads in model dimensions
  ! format: #origin_x #origin_z #end_x #end_z
  call tomo_read_next_line(IIN,string_read)
  read(string_read,*) ORIGIN_X, ORIGIN_Z, END_X, END_Z
  ! --------------------------------------------------------------------------------------
  ! model increments
  ! format: #dx #dy #dz
  ! --------------------------------------------------------------------------------------
  call tomo_read_next_line(IIN,string_read)
  read(string_read,*) SPACING_X, SPACING_Z
  ! --------------------------------------------------------------------------------------
  ! reads in models entries
  ! format: #nx #ny #nz
  ! --------------------------------------------------------------------------------------
  call tomo_read_next_line(IIN,string_read)
  read(string_read,*) NX,NZ
  ! --------------------------------------------------------------------------------------
  ! reads in models min/max statistics
  ! format: #vp_min #vp_max #vs_min #vs_max #density_min #density_max
  ! --------------------------------------------------------------------------------------
  call tomo_read_next_line(IIN,string_read)
  read(string_read,*)  VP_MIN,VP_MAX,VS_MIN,VS_MAX,RHO_MIN,RHO_MAX

  ! Determines total maximum number of element records
  nrecord = int(NX*NZ)

  ! allocate models parameter records
  allocate(x_tomography(nrecord),z_tomography(nrecord),vp_tomography(nrecord),vs_tomography(nrecord), &
           rho_tomography(nrecord),stat=ier)
  allocate(x_tomo(NX),z_tomo(NX),vp_tomo(NX,NZ),vs_tomo(NX,NZ),rho_tomo(NX,NZ),stat=ier)
  if (ier /= 0) call exit_MPI('not enough memory to allocate tomo arrays')

  ! Checks the number of records for points definition while storing them
  irecord = 0
  do while (ier == 0)
    read(IIN,*,iostat=ier) x_tomography(irecord+1),z_tomography(irecord+1),vp_tomography(irecord+1),vs_tomography(irecord+1), &
           rho_tomography(irecord+1)
    if (irecord < NX) x_tomo(irecord+1) = x_tomography(irecord+1)

    if (ier == 0) irecord = irecord + 1
  enddo

  z_tomo = z_tomography(::NX)

  do i = 1,NX
    do j = 1,NZ
      vp_tomo(i,j) = vp_tomography(NX*(j-1)+i)
      vs_tomo(i,j) = vs_tomography(NX*(j-1)+i)
      rho_tomo(i,j) = rho_tomography(NX*(j-1)+i)
    enddo
  enddo

  if (irecord /= nrecord .and. myrank == 0) then
     print *, 'Error: ',trim(TOMOGRAPHY_FILE),' has invalid number of records'
     print *, '     number of grid points specified (= NX*NZ):',nrecord
     print *, '     number of file lines for grid points        :',irecord
     stop 'Error in tomography data file for the grid points definition'
  endif

  if (myrank == 0) then
    write(IOUT,*) '     Number of grid points = NX*NZ:',nrecord
    write(IOUT,*)
  endif

  ! closes file
  close(IIN)
  deallocate(x_tomography,z_tomography,vp_tomography,vs_tomography,rho_tomography)

end subroutine read_tomo_file

!
! ----------------------------------------------------------------------------------------
!

subroutine tomo_read_next_line(unit_in,string_read)

  implicit none

  integer :: unit_in
  character(len=150) :: string_read

  integer :: ier

  do
     read(unit=unit_in,fmt="(a)",iostat=ier) string_read
     if (ier /= 0) stop 'error while reading tomography file'

     ! suppress leading white spaces, if any
     string_read = adjustl(string_read)

     ! suppress trailing carriage return (ASCII code 13) if any (e.g. if input text file coming from Windows/DOS)
     if (index(string_read,achar(13)) > 0) string_read = string_read(1:index(string_read,achar(13))-1)

     ! exit loop when we find the first line that is not a comment or a white line
     if (len_trim(string_read) == 0) cycle
     if (string_read(1:1) /= '#') exit
  enddo

  ! suppress trailing white spaces, if any
  string_read = string_read(1:len_trim(string_read))

  ! suppress trailing comments, if any
  if (index(string_read,'#') > 0) string_read = string_read(1:index(string_read,'#')-1)

  ! suppress leading and trailing white spaces again, if any, after having suppressed the leading junk
  string_read = adjustl(string_read)
  string_read = string_read(1:len_trim(string_read))

end subroutine tomo_read_next_line

!
! ----------------------------------------------------------------------------------------
!

module interpolation
! ----------------------------------------------------------------------------------------
! This module contains two functions for bilinear interpolation
! (modified from http://www.shocksolution.com)
! ----------------------------------------------------------------------------------------
  use constants,only: CUSTOM_REAL

  contains

  ! ====================== Implementation part ===============

  function binarysearch(length, array, value, delta)
    ! Given an array and a value, returns the index of the element that
    ! is closest to, but less than, the given value.
    ! Uses a binary search algorithm.
    ! "delta" is the tolerance used to determine if two values are equal
    ! if ( abs(x1 - x2) <= delta) then assume x1 = x2
    ! endif

    implicit none

    integer, intent(in) :: length
    real(kind=CUSTOM_REAL), dimension(length), intent(in) :: array
    !f2py depend(length) array
    double precision, intent(in) :: value
    double precision, intent(in), optional :: delta

    ! Local variables
    integer :: binarysearch
    integer :: left, middle, right
    real(kind=CUSTOM_REAL) :: d

    if (present(delta) .eqv. .true.) then
      d = delta
    else
      d = 1e-9
    endif
    left = 1
    right = length
    do
      if (left > right) then
        exit
      endif
      middle = nint((left+right) / 2.0)
      if ( abs(array(middle) - value) <= d) then
        binarySearch = middle
      if(binarysearch == length) then
        binarysearch = middle - 1
      else
        binarysearch = middle
      endif
        return
      else if (array(middle) > value) then
        right = middle - 1
      else
        left = middle + 1
      end if
    end do

  end function binarysearch
  
  !
  !-------------------------------------------------------------------------------------------------
  !

  real(kind=CUSTOM_REAL) function interpolate(x_len, x_array, y_len, y_array, f, x, y, delta)
    ! This function uses bilinear interpolation to estimate the value
    ! of a function f at point (x,y)
    ! f is assumed to be sampled on a regular grid, with the grid x values specified
    ! by x_array and the grid y values specified by y_array
    ! Reference: http://en.wikipedia.org/wiki/Bilinear_interpolation

    implicit none
    integer, intent(in) :: x_len, y_len
    real(kind=CUSTOM_REAL), dimension(x_len), intent(in) :: x_array
    real(kind=CUSTOM_REAL), dimension(y_len), intent(in) :: y_array
    real(kind=CUSTOM_REAL), dimension(x_len, y_len), intent(in) :: f
    double precision, intent(in) :: x,y
    double precision, intent(in), optional :: delta
    !f2py depend(x_len) x_array, f
    !f2py depend(y_len) y_array, f

    ! Local variables
    real(kind=CUSTOM_REAL) :: denom, x1, x2, y1, y2
    integer :: i,j
    real(kind=CUSTOM_REAL) :: d

    if (present(delta) .eqv. .true.) then
      d = delta
    else
      d = 1e-9
    endif
    i = binarysearch(x_len, x_array, x, delta) ! binarysearch(x_len, x_array, x)
    j = binarysearch(y_len, y_array, y, delta) ! binarysearch(y_len, y_array, y)
    x1 = x_array(i)
    x2 = x_array(i+1)
    y1 = y_array(j)
    y2 = y_array(j+1)
    denom = (x2 - x1)*(y2 - y1)
    interpolate = (f(i,j)*(x2-x)*(y2-y) + f(i+1,j)*(x-x1)*(y2-y) + &
                  f(i,j+1)*(x2-x)*(y-y1) + f(i+1, j+1)*(x-x1)*(y-y1))/denom

  end function interpolate

end module interpolation