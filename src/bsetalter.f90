MODULE bsetalter

  use globvars
  use Ham
  use alarrays
  use outputs

!***********************************************************************************!
!*
!*         Basis Set alteration module Module
!*
!*   Contains subroutines for:
!*
!*      1) Relocating the wavefunction on a static grid
!*      2) Leaking the basis set, used for large q values in the Hennon-Heiles model
!*      3) Cloning subroutine, which increases the basis set, used mainly for the
!*              spin boson model
!*      4) Retriving cloning information from previous calculations when using the
!*              AIMC-MCE propagation system
!*
!***********************************************************************************!

contains


!--------------------------------------------------------------------------------------------------

  subroutine reloc_basis(bsnew, bsold, x) ! Relocation for MCEv1 or MCEv2 after cloning

    implicit none

    type(basisfn), dimension(:), allocatable, intent(inout) :: bsnew   ! This is the new basis set
    type(basisfn), dimension(:), allocatable, intent(inout) :: bsold   ! This is the previous basis set.
    integer, intent(in) :: x

    complex(kind=8), dimension (:,:), allocatable :: ovrlp_mat
    complex(kind=8), dimension (:), allocatable :: cnew, dnew
    complex(kind=8) :: sumamps
    integer :: j, k, r, ierr, nbfnew, nbfold

    if (errorflag .ne. 0) return

    nbfnew = size(bsnew)
    nbfold = size(bsold)

    if (method=="MCEv1") then
      do j=1,nbfold
        sumamps = (0.0d0, 0.0d0)
        do r=1,npes
          sumamps = sumamps + dconjg(bsold(j)%a_pes(r))*bsold(j)%a_pes(r)
        end do
        
        bsold(j)%D_big = cdsqrt(sumamps)
        
        do r=1,npes
          bsold(j)%d_pes(r) = bsold(j)%d_pes(r)/bsold(j)%D_big
          bsold(j)%a_pes(r) = bsold(j)%d_pes(r) * cdexp (i*bsold(j)%s_pes(r))
        end do
      end do
      
      do j=1,nbfnew
        sumamps = (0.0d0, 0.0d0)
        do r=1,npes
          sumamps = sumamps + dconjg(bsnew(j)%a_pes(r))*bsnew(j)%a_pes(r)
        end do
        
        bsnew(j)%D_big = cdsqrt(sumamps)
        
        do r=1,npes
          bsnew(j)%d_pes(r) = bsnew(j)%d_pes(r)/bsnew(j)%D_big
          bsnew(j)%a_pes(r) = bsnew(j)%d_pes(r) * cdexp (i*bsnew(j)%s_pes(r))
        end do
      end do
      
    end if

    allocate (cnew(nbfnew), stat=ierr)
    if (ierr==0) allocate (ovrlp_mat(nbfnew,nbfold), stat=ierr)
    if (ierr/=0) then
      write (0,"(a)") "Error in allocating temporary z values for reprojection subroutine"
      errorflag=1
      return
    end if

    ! Ovrlp_mat is the overlap with the initial wavepacket
    do j=1,nbfold
      do k=1,nbfnew
        cnew(k) = (0.0d0, 0.0d0)
        sumamps = (0.0d0, 0.0d0)
        do r=1,npes
          sumamps = sumamps + dconjg(bsnew(k)%a_pes(r))*bsold(j)%a_pes(r)
        end do
        ovrlp_mat(k,j) = ovrlpij(bsnew(k)%z(:), bsold(j)%z(:)) * sumamps
      end do
    end do

    do r=1,npes
      cnew(:) = matmul(ovrlp_mat,bsold(:)%D_big)
    end do

    deallocate(ovrlp_mat, stat=ierr)
    if (ierr==0) allocate (ovrlp_mat(nbfnew,nbfnew), stat=ierr)
    if (ierr/=0) then
      write (0,"(a,a)") "Error in de- and re-allocation of first overlap matrix in reprojection subroutine"
      errorflag = 1
      return
    end if

    ovrlp_mat = ovrlpphimat(bsnew)

    allocate (dnew(nbfnew), stat=ierr)
    if (ierr/=0) then
      write (0,"(a,a)") "Error in allocation of dnew in reprojection subroutine"
      errorflag=1
      return
    end if

    
    do r=1,npes
      call lineq(ovrlp_mat, cnew, dnew) 
    end do

    deallocate(ovrlp_mat, stat=ierr)
    if (ierr/=0) then
      write (0,"(a,a)") "Error in deallocation of input overlap"
      errorflag=1
      return
    end if

    do k=1,nbfnew
      bsnew(k)%D_big = dnew(k)
    end do

    if (method=="MCEv1") then
      do j=1,nbfnew
        do r=1,npes
          bsnew(j)%d_pes(r) = bsnew(j)%d_pes(r)*bsnew(j)%D_big
          bsnew(j)%a_pes(r) = bsnew(j)%d_pes(r) * cdexp (i*bsnew(j)%s_pes(r))
        end do
        bsnew(j)%D_big = (1.0d0,0.0d0)
      end do
      do j=1,nbfold
        do r=1,npes
          bsold(j)%d_pes(r) = bsold(j)%d_pes(r)*bsold(j)%D_big
          bsold(j)%a_pes(r) = bsold(j)%d_pes(r) * cdexp (i*bsold(j)%s_pes(r))
        end do
        bsold(j)%D_big = (1.0d0,0.0d0)
      end do
    end if

    deallocate(dnew, stat=ierr)
    if (ierr/=0) then
      write (0,"(a)") "Error deallocating dnew arrays in reloc"
      errorflag = 1
      return
    end if

    return

  end subroutine reloc_basis

!--------------------------------------------------------------------------------------------------

  subroutine cloning(bs,nbf,x,time,clone, clonenum, reps)

    !!NOTE: Cloning is only set up for 2 PESs. This needs to be generalised!

    implicit none

    type(basisfn), dimension(:), allocatable, intent(inout) :: bs
    type(basisfn), dimension(:), allocatable :: bsnew
    real(kind=8), intent(in) :: time
    integer, dimension(:), allocatable, intent(inout) :: clone, clonenum
    integer, intent (inout) :: nbf
    integer, intent (in) :: x, reps
    complex(kind=8), dimension (:), allocatable :: dz
    real(kind=8), dimension (:), allocatable :: dummy_arr, length, phi
    real(kind=8) :: brforce, normar, sumamps, p, q, pqsqrd, deltaprob, phaseval, dist
    integer, dimension(:), allocatable :: clonehere, clonecopy, clonecopy2
    integer :: k, m, j, n, nbfnew, ierr, r, s, clonetype, dummy1, dummy2
    character(LEN=3)::rep

    if (errorflag==1) return

    if ((cloneflg=="YES").or.(cloneflg=="QSC").or.((cloneflg=="BLIND+").and.(x.ne.0))) then
      clonetype = 1 ! 1=conditional cloning, 2=blind cloning
    else if ((cloneflg=="BLIND").or.((cloneflg=="BLIND+").and.(x.eq.0))) then
      clonetype = 2
    else
      write (0,"(2a)") "Cloneflg is invalid. Should be 'YES', 'BLIND' or 'BLIND+', but was ", cloneflg
      errorflag = 1
      return
    end if

    allocate (clonehere(nbf), stat=ierr)
    if (ierr==0) allocate(clonecopy(nbf), stat=ierr)
    if (ierr==0) allocate(clonecopy2(nbf), stat=ierr)
    if (ierr/=0) then
      write (0,"(a)") "Error allocating the clonehere array"
      errorflag = 1
      return
    end if

    if (npes.ne.2) then
      write(6,*) "Error. Cloning currently only valid for npes=2"
      errorflag = 1
      return
    end if

    do k=1,nbf
      if (clone(k).lt.x-clonefreq) clone(k)=0
      clonehere(k) = 0
    end do
    ! Build the map of which trajectories to clone, done on the basis function by basis function level (clonetype=1),
    ! or the entire basis set at once (clonetype=2)

    if (clonetype==1) then
      do k=1,nbf
        normar = 0.0d0
        do r=1,npes
          normar = normar + dconjg(bs(k)%a_pes(r))*bs(k)%a_pes(r)
        end do
        !!!!! The line below needs changing to acount for multiple PESs
        brforce = ((abs(bs(k)%a_pes(1)*bs(k)%a_pes(2))**2.0)/(normar**2.0))
        if ((brforce.gt.thresh).and.(clone(k)==0).and.(clonenum(k).lt.clonemax)) then
          clone(k) = x
          clonehere(k) = 1
        end if
        clonecopy(k) = clone(k)
        clonecopy2(k) = clonenum(k)
      end do
    else if (clonetype==2) then
      if (mod(x,clonefreq)==0) then
        do k=1,nbf
          if (clonenum(k).lt.clonemax) then
            clone(k) = x
            clonehere(k) = 1
          end if
        end do
      end if
      do k=1,nbf
        clonecopy(k) = clone(k)
        clonecopy2(k) = clonenum(k)
      end do

    end if

    ! build new sized clone mapping arrays to use for next itteration

    nbfnew = nbf + sum(clonehere(:))

    deallocate (clone, stat=ierr)
    if (ierr==0) deallocate (clonenum, stat=ierr)
    if (ierr==0) allocate (clone(nbfnew), stat=ierr)
    if (ierr==0) allocate (clonenum(nbfnew), stat=ierr)
    if (ierr/=0) then
      write (0,"(a)") "Error in de- and re-allocation of clone arrays"
      errorflag = 1
      return
    end if
    do k=1,nbf
      clone(k) = clonecopy(k)
      clonenum(k) = clonecopy2(k)
    end do
    deallocate(clonecopy, stat=ierr)
    if (ierr==0) deallocate(clonecopy2, stat=ierr)
    if (ierr/=0) then
      write(0,"(a)") "Error deallocating the cloning copy arrays"
      errorflag = 1
      return
    end if

    ! Actual cloning section

    if (nbfnew/=nbf) then

      call allocbs(bsnew, nbfnew)

      j=1

      write(rep,"(i3.3)") reps
      open(unit=47756,file="Clonetrack-"//trim(rep)//".out",status="old",access="append",iostat=ierr)

      allocate (dz(ndim), stat=ierr)
      if (ierr/=0) then
        write(0,'(a)') "Error in allocating dz array for MCEv1 cloning/relocation"
        errorflag = 1
        return
      end if

      if (cloneflg=="QSC") then
        clonetype = 3
      else if (method=="MCEv2") then
        clonetype = 1
      else if (method=="MCEv1") then
        clonetype = 2
      end if

      do k=1,nbf

        if (clonehere(k) == 1) then
          clone(k) = x
          clone(nbf+j) = x
          clonenum(k) = clonenum(k) + 1
          clonenum(nbf+j) = clonenum(k)

          if (clonetype==1) then

            ! First child trajectory
            bsnew(k)%D_big = bs(k)%D_big * abs(bs(k)%a_pes(in_pes))
            bsnew(k)%d_pes(in_pes) = bs(k)%d_pes(in_pes)/abs(bs(k)%a_pes(in_pes))
            do r=1,npes
              if (r.ne.in_pes) then
                bsnew(k)%d_pes(r) = (0.0d0,0.0d0)
              end if
              bsnew(k)%s_pes(r) = bs(k)%s_pes(r)
              bsnew(k)%a_pes(r) = bsnew(k)%d_pes(r) * cdexp(i*bsnew(k)%s_pes(r))
            end do
            do m=1,ndim
              bsnew(k)%z(m) = bs(k)%z(m)
            end do

            ! Second child trajectory
            bsnew(nbf+j)%D_big = bs(k)%D_big * sqrt(1.-(dconjg(bs(k)%a_pes(in_pes))*bs(k)%a_pes(in_pes)))
            bsnew(nbf+j)%d_pes(in_pes) = (0.0d0,0.0d0)
            do r=1,npes
              if (r.ne.in_pes) then
                if (x.eq.0) then
                  bsnew(nbf+j)%d_pes(r) = (1.0d0,0.0d0)
                else
                  bsnew(nbf+j)%d_pes(r) = bs(k)%d_pes(r)/&
                                  sqrt(1.-(dconjg(bs(k)%a_pes(in_pes))*bs(k)%a_pes(in_pes)))
                end if
              end if
              bsnew(nbf+j)%s_pes(r) = bs(k)%s_pes(r)
              bsnew(nbf+j)%a_pes(r) = bsnew(nbf+j)%d_pes(r) * cdexp(i*bsnew(nbf+j)%s_pes(r))
            end do
            do m=1,ndim
              bsnew(nbf+j)%z(m) = bs(k)%z(m)
            end do

          else if (clonetype==2) then

            !!!!!!!!!!NOTE!!!!!!!!!!!

            !This is only half of the MCEv1 cloning procedure. After cloning occurs,
            !the reloc_basis subroutine is called to recalculate the amplitudes.
            ! Checking that the reloc function works as expected would be a good place to start

            ! First child trajectory
            bsnew(k)%D_big = bs(k)%D_big
            bsnew(k)%d_pes(in_pes) = bs(k)%d_pes(in_pes)
            do m=1,ndim
              dz(m)=cmplx(ZBQLNOR(dble(bs(k)%z(m)),sqrt(0.5d0)),ZBQLNOR(dimag(bs(k)%z(m)),sqrt(0.5)))
            end do
            do r=1,npes
              if (r.ne.in_pes) then
                bsnew(k)%d_pes(r) = (0.0d0,0.0d0)
              end if
              bsnew(k)%s_pes(r) = bs(k)%s_pes(r)
              bsnew(k)%a_pes(r) = bsnew(k)%d_pes(r) * cdexp(i*bsnew(k)%s_pes(r))
            end do
            do m=1,ndim
              bsnew(k)%z(m) = bs(k)%z(m) - dz(m)
            end do

            ! Second child trajectory
            bsnew(nbf+j)%D_big = bs(k)%D_big
            bsnew(nbf+j)%d_pes(in_pes) = (0.0d0,0.0d0)
            do r=1,npes
              if (r.ne.in_pes) then
                if (x.eq.0) then
                  bsnew(nbf+j)%d_pes(r) = (1.0d0,0.0d0)
                else
                  bsnew(nbf+j)%d_pes(r) = bs(k)%d_pes(r)
                end if
              end if
              bsnew(nbf+j)%s_pes(r) = bs(k)%s_pes(r)
              bsnew(nbf+j)%a_pes(r) = bsnew(nbf+j)%d_pes(r) * cdexp(i*bsnew(nbf+j)%s_pes(r))
            end do
            do m=1,ndim
              bsnew(nbf+j)%z(m) = bs(k)%z(m) + dz(m)
            end do

          else if (clonetype==3) then

          !!CCS circular distribution of amplitudes - generalised to n potential energy surfaces

          allocate(length(npes),phi(npes))

          !First Child Trajectory

          do r=1,npes
            dummy1 = 0
            do while (dummy1 .eq. 0)
              call random_number(length(r))
              call random_number(phi(r))
              phi(r) = phi(r) * 2.0d0 * pirl
              if (r == 1) then
                dummy1 = 1
              else
                do s = 1,r-1
                  !!!! Check that the amplitude values would be sufficiently separated
                  !!!! in the complex plane. This does not seem very efficient however.
                  dist = 0.0d0
                  dist = (length(r)*dcos(phi(r))-length(s)*dcos(phi(s)))**2
                  dist = dist + (length(r)*dsin(phi(r))-length(s)*dsin(phi(s)))**2
                  dist = sqrt(dist)
                  if (dist > qsce) then
                    dummy1 = 1
                  end if
                  !!!! Below checks no two amplitudes would stimulate cloning.
                  !!!! Valid for 2 PESs, but the calculations would change for a more general case
                  !!!! since the cloning is not stimulated by only a single pair of PES components
                  if (dummy1 == 0) then
                    dist = (length(r)**2)*(length(s)**2)/(length(r)**2)+(length(s)**2)
                    if (dist > thresh) then
                      dummy1 = 1
                    end if
                  end if
                end do
              end if
            end do
          end do

          do r=1,npes
            bsnew(k)%a_pes(r) = cmplx(length(r)*dcos(phi(r)),length(r)*dsin(phi(r)),kind=8)
          end do

          !Second Child Trajectory

          do r=1,npes
            s = npes - (r-1)
            if (r .le. (npes/2.)) then
              bsnew(nbf+j)%a_pes(r) = cmplx(length(s)*dcos(phi(s)),(-1.0d0)*length(s)*dsin(phi(s)),kind=8)
            else
              bsnew(nbf+j)%a_pes(r) = cmplx((-1.0d0)*length(s)*dcos(phi(s)),length(s)*dsin(phi(s)),kind=8)
            end if
            if ((mod(npes,2)==1).and.(r==int(floor(real(npes)/2.))+1)) then
              bsnew(nbf+j)%a_pes(r) = cmplx(0.0d0*dcos(phi(r)),0.0d0*dsin(phi(r)),kind=8)
            end if
          end do

          deallocate (length, phi)

          do m=1,ndim
            bsnew(k)%z(m) = bs(k)%z(m)
            bsnew(nbf+j)%z(m) = bs(k)%z(m)
          end do
          do r= 1,npes
            bsnew(k)%s_pes(r) = bs(k)%s_pes(r)
            bsnew(k)%d_pes(r) = bsnew(k)%a_pes(r) * cdexp(-i*bsnew(k)%s_pes(r))
            bsnew(nbf+j)%s_pes(r) = bs(k)%s_pes(r)
            bsnew(nbf+j)%d_pes(r) = bsnew(nbf+j)%a_pes(r) * cdexp(-i*bsnew(nbf+j)%s_pes(r))
          end do


!          !!OAB circular distribution amplitudes

!            dummy1 = 0
!            do while (dummy1.eq.0)
!              dummy2 = 0
!              do while(dummy2.eq.0)
!                call random_number(p)
!                call random_number(q)
!                pqsqrd = (p**2)+(q**2)
!                if (pqsqrd <1) then
!                  dummy2 = 1
!                end if
!              end do
!              p = p/sqrt(pqsqrd)
!              q = q/sqrt(pqsqrd)
!              deltaprob = abs((p**2)-(q**2))
!              if (deltaprob > qsce) then
!                dummy1 = 1
!              end if
!            end do
!            call random_number(phaseval)
!            phaseval = phaseval * 2.0d0 * pirl
!
!            !Assign First child trajectory a'1
!            bsnew(k)%a_pes(1) = cmplx(p,0.0d0,kind=8)
!            !Assign First child trajectory a'2
!            bsnew(k)%a_pes(2) = cmplx(q*dcos(phaseval),q*dsin(phaseval),kind=8)
!            !Assign Second child trajectory to be orthogonal a"1
!            bsnew(nbf+j)%a_pes(1)= cmplx(q*dcos(phaseval),-1.0d0*q*dsin(phaseval),kind=8)
!            !Assign Second child trajectory to be orthogonal a"2
!            bsnew(nbf+j)%a_pes(2)= cmplx(-p,0.0d0,kind=8)
!
!            do m=1,ndim
!              bsnew(k)%z(m) = bs(k)%z(m)
!              bsnew(nbf+j)%z(m) = bs(k)%z(m)
!            end do
!            do r= 1,npes
!              bsnew(k)%s_pes(r) = bs(k)%s_pes(r)
!              bsnew(k)%d_pes(r) = bsnew(k)%a_pes(r) * cdexp(-i*bsnew(k)%s_pes(r))
!              bsnew(nbf+j)%s_pes(r) = bs(k)%s_pes(r)
!              bsnew(nbf+j)%d_pes(r) = bsnew(nbf+j)%a_pes(r) * cdexp(-i*bsnew(nbf+j)%s_pes(r))
!            end do

!            !!CCS square distribution of amplitudes

!            do r=1,npes
!              !First child trajectory
!              sumamps = 0.0d0
!              q = q * 2.0 - 1.0     ! possibly try modifying the range to enforce close to pes amplitudes
!              p = p * 2.0 - 1.0
!              bsnew(k)%d_pes(r) = cmplx(q,p,kind=8)
!              sumamps = sumamps + dsqrt(dble(cmplx(q,p,kind=8) * cmplx(q,-1.0*p,kind=8)))
!            end do
!            do r=1,npes
!              bsnew(k)%d_pes(r) = bsnew(k)%d_pes(r) / sumamps
!              bsnew(k)%s_pes(r) = bs(k)%s_pes(r)
!              bsnew(k)%a_pes(r) = bsnew(k)%d_pes(r) * cdexp(i*bsnew(k)%s_pes(r))
!            end do
!            do m=1,ndim
!              bsnew(k)%z(m) = bs(k)%z(m)
!            end do
!
!            !Second child trajectory
!            sumamps = 0.0d0
!            do r=1,npes
!              call random_number(q)
!              call random_number(p)
!              q = q * 2.0 - 1.0     ! possibly try modifying the range to enforce close to pes amplitudes
!              p = p * 2.0 - 1.0
!              bsnew(nbf+j)%d_pes(r) = cmplx(q,p,kind=8)
!              sumamps = sumamps + dsqrt(dble(cmplx(q,p,kind=8) * cmplx(q,-1.0*p,kind=8)))
!            end do
!            do r=1,npes
!              bsnew(nbf+j)%d_pes(r) = bsnew(nbf+j)%d_pes(r) / sumamps
!              bsnew(nbf+j)%s_pes(r) = bs(k)%s_pes(r)
!              bsnew(nbf+j)%a_pes(r) = bsnew(nbf+j)%d_pes(r) * cdexp(i*bsnew(nbf+j)%s_pes(r))
!            end do
!            do m=1,ndim
!              bsnew(nbf+j)%z(m) = bs(k)%z(m)
!            end do

            !Modifications to capital D amplitudes

            bsnew(k)%D_big = bs(k)%D_big * (bsnew(nbf+j)%a_pes(2)*bs(k)%a_pes(1)-bsnew(nbf+j)%a_pes(1)*bs(k)%a_pes(2))
            bsnew(nbf+j)%D_big = bs(k)%D_big * (bsnew(k)%a_pes(1)*bs(k)%a_pes(2)-bsnew(k)%a_pes(2)*bs(k)%a_pes(1))

            bsnew(k)%D_big = bsnew(k)%D_big/&
                    (bsnew(k)%a_pes(1)*bsnew(nbf+j)%a_pes(2)-bsnew(k)%a_pes(2)*bsnew(nbf+j)%a_pes(1))
            bsnew(nbf+j)%D_big = bsnew(nbf+j)%D_big/&
                    (bsnew(k)%a_pes(1)*bsnew(nbf+j)%a_pes(2)-bsnew(k)%a_pes(2)*bsnew(nbf+j)%a_pes(1))

          end if

          write(47756,"(3i5,2es25.17e3)") x, k, nbf+j, abs(bs(k)%a_pes(in_pes)), sqrt(1.-((abs(bs(k)%a_pes(in_pes))**2.0d0)))
          j = j+1

        else

          bsnew(k)%D_big = bs(k)%D_big
          do r=1,npes
            bsnew(k)%d_pes(r) = bs(k)%d_pes(r)
            bsnew(k)%s_pes(r) = bs(k)%s_pes(r)
            bsnew(k)%a_pes(r) = bsnew(k)%d_pes(r) * cdexp(i*bsnew(k)%s_pes(r))
          end do
          do m=1,ndim
            bsnew(k)%z(m) = bs(k)%z(m)
          end do

        end if

      end do

      close (47756)

      if (method=="MCEv1") call reloc_basis(bsnew, bs, x)

      call deallocbs(bs)
      call allocbs(bs, nbfnew)

      do k=1,nbfnew
        bs(k)%D_big = bsnew(k)%D_big
        do r=1,npes
          bs(k)%a_pes(r) = bsnew(k)%a_pes(r)
          bs(k)%d_pes(r) = bsnew(k)%d_pes(r)
          bs(k)%s_pes(r) = bsnew(k)%s_pes(r)
        end do
        do m=1,ndim
          bs(k)%z(m) = bsnew(k)%z(m)
        end do
      end do

      call deallocbs(bsnew)

      n = nbfnew-nbf

      write (6,"(i0,a,i0,a,i0)") sum(clonehere(:)), " bfs cloned in step ", x, &
            ". nbf now = ", nbfnew

      nbf = nbfnew

    end if

    deallocate(clonehere, stat=ierr)
    if (ierr/=0) then
      write(0,"(a)") "Error deallocating the clone-here array"
      errorflag = 1
      return
    end if

  end subroutine cloning


  subroutine v1cloning(bs,nbf,clone1,clone2)
    implicit none 

    type(basisfn), dimension(:), allocatable, intent(inout) :: bs
    type(basisfn), dimension(:), intent(inout) ::clone1, clone2 
    integer, intent(in) :: nbf
    integer :: nbfold, k, m, r, nbfnew, ierr, l, j, cloneload, i_seed, n
    INTEGER, DIMENSION(:), ALLOCATABLE :: a_seed, loc0
    INTEGER, DIMENSION(1:8) :: dt_seed
    real(kind=8) :: brforce, normar, sumamps, trackav
    complex(kind=8), dimension(size(bs),size(bs))::cloneovrlp, clone2ovrlp, bsovrlp
    complex(kind=8) :: clonenorm, clonenorm2, asum1, asum2, bsnorm
    real(kind=8) :: normc1, normc2, normc0, choice, pophold1, pophold2

    ! write(6,*) "Starting new V1 cloning subroutine"
    bsovrlp = ovrlpmat(bs)
    bsnorm = norm(bs,bsovrlp)
    pophold1 = pop(bs,1,bsovrlp)
    pophold2 = pop(bs,2,bsovrlp)
    !write(6,*) "basenorm1 = ", bsnorm, pophold1,pophold2
    !manipulating the child amplitudes 
    do k=1, nbf
      do m=1, ndim
        clone1(k)%z(m) = bs(k)%z(m)
        clone2(k)%z(m) = bs(k)%z(m)
      end do
  
      clone2(k)%D_big = (1.0d0,0.00)
      clone2(k)%d_pes(1) = (0.0d0,0.0d0) 
      clone2(k)%d_pes(2) = bs(k)%d_pes(2) 
      clone2(k)%s_pes(1) = bs(k)%s_pes(1)
      clone2(k)%s_pes(2) = bs(k)%s_pes(2)
      clone2(k)%a_pes(1) = clone2(k)%d_pes(1) * exp(i*clone2(k)%s_pes(1))
      clone2(k)%a_pes(2) = clone2(k)%d_pes(2) * exp(i*clone2(k)%s_pes(2))

      clone1(k)%D_big = (1.0d0,0.00)
      clone1(k)%d_pes(1) = bs(k)%d_pes(1) ! it's easier to set all the first child to the preclone value and change later 
      clone1(k)%d_pes(2) = (0.0d0,0.0d0)
      clone1(k)%s_pes(1) = bs(k)%s_pes(1)
      clone1(k)%s_pes(2) = bs(k)%s_pes(2)
      clone1(k)%a_pes(1) = clone1(k)%d_pes(1) * exp(i*clone1(k)%s_pes(1)) 
      clone1(k)%a_pes(2) = clone1(k)%d_pes(2) * exp(i*clone1(k)%s_pes(2)) 
    end do 
    

    bsovrlp = ovrlpmat(bs)
    bsnorm = norm(bs,bsovrlp)
    pophold1 = pop(bs,1,bsovrlp)
    pophold2 = pop(bs,2,bsovrlp)
    cloneovrlp = ovrlpmat(clone1)
    clone2ovrlp = ovrlpmat(clone2)
    clonenorm = norm(clone1,cloneovrlp)
    clonenorm2 = norm(clone2,clone2ovrlp)
    normc1 = sqrt(clonenorm*dconjg(clonenorm))
    normc2 = sqrt(clonenorm2*dconjg(clonenorm2))
    ! write(6,*) "basenorm2 = ", bsnorm, pophold1,pophold2
    ! write(6,*) "clonenorm = ", clonenorm
    ! write(6,*) "clonenorm2 = ", clonenorm2



    do k=1, nbf
      clone1(k)%orgpes = 1 
      clone2(k)%orgpes = 2
      do r=1, npes
        clone2(k)%d_pes(r) = clone2(k)%d_pes(r)!/sqrt(clonenorm2)!exp(-i*clone(k)%s_pes(r)) ! clone 2 will be non zero only when not on the pes
        clone1(k)%d_pes(r) = clone1(k)%d_pes(r)!/sqrt(clonenorm)!exp(-i*clone(k)%s_pes(r)) ! it's easier to set all the first child to the preclone value and change later 
        clone1(k)%a_pes(r) = clone1(k)%d_pes(r) * exp(i*clone1(k)%s_pes(r))
        clone2(k)%a_pes(r) = clone2(k)%d_pes(r) * exp(i*clone2(k)%s_pes(r))
      end do 
    end do  
      
    write(6,*) "finished original cloning"
    
  end subroutine v1cloning

  subroutine bstransfer(bsnew,bsold,nbf)
    implicit none

    type(basisfn), dimension(:), allocatable, intent(inout) :: bsnew,bsold
    integer, intent(in) :: nbf
    integer :: k, m, r



    do k=1, nbf
      do m=1, ndim
        bsnew(k)%z(m) = bsold(k)%z(m)
      end do
      bsnew(k)%D_big = (1.0d0,0.00) ! the prefactor doesn't change through cloning 

      do r=1, npes
        bsnew(k)%d_pes(r) = bsold(k)%d_pes(r) 
        bsnew(k)%s_pes(r) = bsold(k)%s_pes(r) 
        bsnew(k)%a_pes(r) = bsold(k)%a_pes(r)
      end do 
      bsnew(k)%orgpes = bsold(k)%orgpes
    end do 




  end subroutine bstransfer

  subroutine Renorm_clones(bs, PES, nbf)
    ! inputted variables
    type(basisfn), dimension(:),  allocatable, intent(inout):: bs
    integer, intent(in) :: PES, nbf

    ! internal variables
    complex(kind=8), dimension(size(bs),size(bs)):: bsovrlp
    complex(kind=8) :: bsnorm
    integer :: not_PES

    ! counters
    integer :: k,r

    if (PES==1) then
      not_pes = 2
    else if (PES==2) then
      not_PES = 1
    end if


    do k=1,nbf
      bs(k)%d_pes(not_PES) = 0.0d0
      bs(k)%a_pes(not_PES) = 0.0d0
    end do 
    bsovrlp = ovrlpmat(bs)
    bsnorm = norm(bs,bsovrlp)
    do k = 1, nbf 
      bs(k)%d_pes(PES) = bs(k)%d_pes(PES)/sqrt(bsnorm)
      bs(k)%a_pes(PES) = bs(k)%d_pes(PES)*exp(i*bs(k)%s_pes(PES))
    end do 
  
  end subroutine Renorm_clones

  subroutine v1cloning_check(bsetarr, cloneblock, e, nbf, nclones,x,clonetype,pops)

    implicit none 

    type(basisset), dimension (:), intent(inout) :: bsetarr
    integer,intent(inout) :: e, nbf, nclones,x
    real,dimension(:),intent(inout), allocatable :: cloneblock
    integer,dimension(:),intent(inout), allocatable :: clonetype

    real(kind=8), dimension (:,:), intent(inout) :: pops
    complex(kind=8), dimension (:,:), allocatable :: ovrlp
    real(kind=8) ::  pophold1,pophold2,poptot, popdiff, normar
    integer, dimension(:), allocatable :: cloned
    real(kind=8), dimension(:), allocatable :: brforce
    integer :: p,j,k,l, clonehere, r


    do p=1,nclones
      allocate(ovrlp(size(bsetarr(p)%bs),size(bsetarr(p)%bs)))
      ovrlp=ovrlpmat(bsetarr(p)%bs)
      popdiff = 1
      pophold1 = pop(bsetarr(p)%bs, 1, ovrlp)
      pophold2 = pop(bsetarr(p)%bs, 2, ovrlp)
      poptot = pophold1 + pophold2
      deallocate(ovrlp) 
      if (poptot.lt.5d-2) then
        ! write(6,*) 'clone', p, 'was skipped due to low population', poptot
        cycle
      end if 
      if(auto_clone=='POP') then
        if ((bsetarr(p)%bs(1)%orgpes==1)) then 
          popdiff = (pophold1-pophold2)/(pophold1+pophold2)
        else if (bsetarr(p)%bs(1)%orgpes == 2) then
          popdiff = (pophold2-pophold1)/(pophold1+pophold2)
        end if 

        if (popdiff.lt.1-(2*nbf_frac)) then 
          if(nclones.lt.2**clonemax) then
            nclones = nclones+1 
            write(6,*) 'clone', nclones, 'created from', p,'at timestep', x, pophold1, pophold2
            !$omp critical
            call v1cloning(bsetarr(p)%bs,nbf,bsetarr(p)%bs,bsetarr(nclones)%bs)
            ! call v1cloning_angular(bsetarr(p)%bs,nbf,bsetarr(p)%bs,bsetarr(nclones)%bs)
            !$omp end critical 
          end if 
        end if
      else if(auto_clone=='NBF') then
        clonehere = 0
        do j=1,nbf
          normar = 0.0d0
          do r=1,npes
            normar = normar + dconjg(bsetarr(p)%bs(j)%a_pes(r))*bsetarr(p)%bs(j)%a_pes(r)
          end do
          !!!! The line below needs changing to acount for multiple PESs
          brforce(j) = ((abs(bsetarr(p)%bs(j)%a_pes(1)*bsetarr(p)%bs(j)%a_pes(2))**2.0)/(normar**2.0))
          if ((brforce(j).gt.thresh)) then
            ! write(brunit,*) 'cloneblock hit for repeat', reps, 'clone', p, 'timestep', x, brforce
            clonehere = clonehere + 1
          end if 
        end do 
        if (clonehere.ge.nbf*nbf_frac) then
            if(nclones.lt.2**clonemax) then 
              nclones = nclones+1 
              call v1cloning(bsetarr(p)%bs,nbf,bsetarr(p)%bs,bsetarr(nclones)%bs)
              ! call v1cloning_angular(bsetarr(p)%bs,nbf,bsetarr(p)%bs,bsetarr(nclones)%bs)
              clonehere = 0 
          end if 
        end if  
      else if (auto_clone== 'NO' .or. auto_clone == 'RAN') then
        if (x==cloneblock(e)) then
          write(6,*) cloneblock
          ! write(6,*) 'cloneblock hit for repeat', reps 
          l = nclones+1
          do j=1,nclones
            !write(6,*) 'here j =, ', j, 'and l =, ', l
            !$omp critical
            write(6,*) "Starting cloning at timestep", x
            call v1cloning(bsetarr(j)%bs,nbf,bsetarr(j)%bs,bsetarr(l)%bs)
            ! call v1cloning_angular(bsetarr(j)%bs,nbf,bsetarr(j)%bs,bsetarr(l)%bs)
            !$omp end critical 
            l = l+1
          end do 
          write(6,*) "clonemax is ", clonemax
          nclones = nclones*2
          e=e+1
          if (e.gt.clonemax) then
            e = 1
            write(6,*) 'reduced e to 1 so cloneblock is now, ', cloneblock(e)
          end if 
        end if
      end if 
    end do 
    ! write(6,*) 'checked cloning conditions'




  end subroutine v1cloning_check

  subroutine v1ctcloning_check(bsetarr, cloneblock, e, nbf, nclones,x,clonetype,pops)
    implicit none 

    type(basisset), dimension (:), intent(inout) :: bsetarr
    integer,intent(inout) :: e, nbf, nclones,x
    real,dimension(:),intent(inout), allocatable :: cloneblock
    integer,dimension(:),intent(inout), allocatable :: clonetype

    real(kind=8), dimension (:,:), intent(inout) :: pops
    complex(kind=8), dimension (:,:), allocatable :: ovrlp
    real(kind=8) ::  pophold1,pophold2,poptot, popdiff, normar
    integer, dimension(:), allocatable :: cloned
    real(kind=8), dimension(:), allocatable :: brforce
    integer :: p,j,k,l, clonehere, r
    
    if (auto_clone == 'TOP' .and. x.gt.1)then 
      
      popdiff = pops(x-1,1) - pops(x-1,2)
      ! write(6,*) popdiff, cloneblock(e)
      if (popdiff.lt.cloneblock(e)) then 
        if (e.le.clonemax) then
          write(6,*) cloneblock
          ! write(6,*) 'cloneblock hit for repeat', reps 
          l = nclones+1
          do j=1,nclones
            !write(6,*) 'here j =, ', j, 'and l =, ', l
            !$omp critical
            if (clonetype(e)==0) then
              write(6,*) "Starting cloning at timestep", x,popdiff
              call v1cloning(bsetarr(j)%bs,nbf,bsetarr(j)%bs,bsetarr(l)%bs)
            else if (clonetype(e)==1) then
              write(6,*) "starting angular cloning at timestep", x,popdiff
              call v1cloning_angular(bsetarr(j)%bs,nbf,bsetarr(j)%bs,bsetarr(l)%bs)
            end if 
            !$omp end critical 

            l = l+1
          end do 
          write(6,*) "clonemax is ", clonemax
          nclones = nclones*2
          e=e+1
          end if 
        end if 
    end if 
    


  end subroutine v1ctcloning_check

  subroutine v1cloning_angular(bs, nbf, clone1, clone2)
    implicit none

    type(basisfn), dimension(:), allocatable, intent(inout) :: bs
    type(basisfn), dimension(:), intent(inout) ::clone1, clone2 
    integer, intent(in) :: nbf
    integer :: nbfold, k, m, r, nbfnew, ierr, l, j, cloneload, i_seed, n
    INTEGER, DIMENSION(:), ALLOCATABLE :: a_seed, loc0
    INTEGER, DIMENSION(1:8) :: dt_seed
    real(kind=8) :: brforce, normar, sumamps, trackav
    complex(kind=8), dimension(size(bs),size(bs))::cloneovrlp, clone2ovrlp, bsovrlp
    complex(kind=8) :: clonenorm, clonenorm2, asum1, asum2, bsnorm
    real(kind=8) :: normc1, normc2, normc0, choice, pophold1, pophold2
    complex(kind=8) :: cos_theta, sin_theta
    ! Set the angle theta (you may want to adjust this value)
    real(kind=8) :: theta

    call random_number(theta)
    theta = theta * 3.1415926535
    write(6,*) "Angular cloning has begun" 
    write(6,*) "theta for this event is, ", theta
    cos_theta = cos(theta)
    sin_theta = sin(theta)


    ! write(6,*) "Starting new V1 cloning subroutine"
    bsovrlp = ovrlpmat(bs)
    bsnorm = norm(bs,bsovrlp)
    pophold1 = pop(bs,1,bsovrlp)
    pophold2 = pop(bs,2,bsovrlp)
    write(6,*) "basenorm1 = ", bsnorm, pophold1,pophold2
    !manipulating the child amplitudes 
    do k=1, nbf
      do m=1, ndim
        clone1(k)%z(m) = bs(k)%z(m)
        clone2(k)%z(m) = bs(k)%z(m)
      end do
  
      clone2(k)%D_big = (1.0d0,0.00)
      clone2(k)%d_pes(1) = bs(k)%d_pes(1) * sin_theta * sin_theta
      clone2(k)%d_pes(2) = bs(k)%d_pes(2) * cos_theta *cos_theta
      clone2(k)%s_pes(1) = bs(k)%s_pes(1)
      clone2(k)%s_pes(2) = bs(k)%s_pes(2)
      clone2(k)%a_pes(1) = clone2(k)%d_pes(1) * exp(i*clone2(k)%s_pes(1))
      clone2(k)%a_pes(2) = clone2(k)%d_pes(2) * exp(i*clone2(k)%s_pes(2))

      clone1(k)%D_big = (1.0d0,0.00) 
      clone1(k)%d_pes(1) = bs(k)%d_pes(1) * cos_theta * cos_theta ! it's easier to set all the first child to the preclone value and change later 
      clone1(k)%d_pes(2) = bs(k)%d_pes(2) * sin_theta * sin_theta
      clone1(k)%s_pes(1) = bs(k)%s_pes(1)
      clone1(k)%s_pes(2) = bs(k)%s_pes(2)
      clone1(k)%a_pes(1) = clone1(k)%d_pes(1) * exp(i*clone1(k)%s_pes(1)) 
      clone1(k)%a_pes(2) = clone1(k)%d_pes(2) * exp(i*clone1(k)%s_pes(2)) 
    end do 
    write(6,*) "Done"

    bsovrlp = ovrlpmat(bs)
    bsnorm = norm(bs,bsovrlp)
    pophold1 = pop(bs,1,bsovrlp)
    pophold2 = pop(bs,2,bsovrlp)
    cloneovrlp = ovrlpmat(clone1)
    clone2ovrlp = ovrlpmat(clone2)
    clonenorm = norm(clone1,cloneovrlp)
    clonenorm2 = norm(clone2,clone2ovrlp)
    normc1 = sqrt(clonenorm*dconjg(clonenorm))
    normc2 = sqrt(clonenorm2*dconjg(clonenorm2))
    write(6,*) "basenorm2 = ", bsnorm, pophold1,pophold2
    write(6,*) "clonenorm = ", clonenorm
    write(6,*) "clonenorm2 = ", clonenorm2



    do k=1, nbf
      clone1(k)%orgpes = 1 
      clone2(k)%orgpes = 2
      do r=1, npes
        clone2(k)%d_pes(r) = clone2(k)%d_pes(r)!/sqrt(clonenorm2)!exp(-i*clone(k)%s_pes(r)) ! clone 2 will be non zero only when not on the pes
        clone1(k)%d_pes(r) = clone1(k)%d_pes(r)!/sqrt(clonenorm)!exp(-i*clone(k)%s_pes(r)) ! it's easier to set all the first child to the preclone value and change later 
        clone1(k)%a_pes(r) = clone1(k)%d_pes(r) * exp(i*clone1(k)%s_pes(r))
        clone2(k)%a_pes(r) = clone2(k)%d_pes(r) * exp(i*clone2(k)%s_pes(r))
      end do 
    end do  

  end subroutine v1cloning_angular


!***********************************************************************************!
end module bsetalter