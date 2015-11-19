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



!
! src/wrapper_cuda/acoustic_cuda.f90
!

subroutine compute_forces_acoustic_GPU()
end subroutine


subroutine compute_stacey_acoustic_GPU()
end subroutine


subroutine compute_add_sources_acoustic_GPU()
end subroutine

!
! src/wrapper_cuda/elastic_cuda.f90
!



subroutine compute_forces_elastic_GPU()
end subroutine


subroutine compute_stacey_viscoelastic_GPU()
end subroutine


subroutine compute_add_sources_viscoelastic_GPU()
end subroutine


!
! src/wrapper_cuda/init_host_to_dev_variable.f90
!


subroutine init_host_to_dev_variable()
end subroutine


!
! src/wrapper_cuda/prepare_timerun_gpu.f90
!


subroutine prepare_timerun_GPU()
end subroutine

