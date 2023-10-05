Program MainMCE

!***********************************************************************************!
!                                                                                   !
!  MCE program - by Chris Symonds     Version 1.01               Date : 04/03/15    !
!                                                                                   !
!  This Program performs simulations using the Multi-Configurational Ehrenfest      !
!  method with the formulations given in D. Shalashilin's 2010 (MCEv2) and          !
!  2009 (MCEv1) papers.                                                             !
!                                                                                   !
!  This uses the ansatz |Psi> = Sum D(a(1)|1>+a(2)|2>+...)|z> and using this        !
!  program can be applied to systems with any number of quantum logical states |n>  !
!  The program has the following stucture in the Main module :                      !
!                                                                                   !
!   1) Read in run conditions. These are generated by the program run shell script  !
!   2) If run conditions allow, a basis set is generated and checked to ensure      !
!            it is normalised                                                       !
!   3) If run conditions allow, the basis set is then propagated in time            !
!   4) Results of propagation are then output                                       !
!                                                                                   !
!  If propagation is allowed but basis set generation is disallowed, a valid basis  !
!  set file, or set of basis set files, must be present in the run folder. This can !
!  be generatedby running the program with only basis set generation allowed.       !
!                                                                                   !
!  Included in this program are various omp statements. These are only active if    !
!  the program is compiled with the -openmp flag (for ifort - other compilers use   !
!  a different flag). This means that when running on arc1 the program can run in   !
!  parallel under a sharedenvironment, however tests can also be carried out on     !
!  chmlin 18 (or a desktop) in serialby not compiling with the open MP flags. The   !
!  choice of flag is automatically chosen by thecompilation script.                 !
!                                                                                   !
!  Two modes of propagation are possible :                                          !
!      1) Static stepsize propagation propagates using the RK4 method with a        !
!         predefined stepsize, outputting the ACF and population data along with    !
!         conserved quantities                                                      !
!      2) Adaptive stepsize propagation uses an algorithm which alters the stepsize !
!         to minimise the error between the fourth and fifth order RK propagation   !
!         systems. This currently outputs a dump of all the timesteps from which a  !
!         histogram is generatedwith which an appropriate static stepsize is        !
!         generated.                                                                !
!                                                                                   !
!                                                                                   !
!  Changelog :                                                                      !
!      25/09/13 - Added Comments and large preamble section to Main and preamble to !
!                 modules                                                           !
!      28/11/13 - Altered the readbasis subroutine so that it now works with the    !
!                 repeat execution                                                  !
!               - Included a small sub-program which can translate initial basis    !
!                 sets between theformat needed for this code and the format needed !
!                 for JKs code                                                      !
!      09/01/14 - Found and remedied errors in the MCEv1 time derivative            !
!                 subroutines, meaning that now both MCE methods normalise and       !
!                 conserve norms.                                                   !
!      17/01/14 - Rearranged variables so that the spin boson specific arrays wm,   !
!                 Cm and sig are now local rather than global. The 6 parameters     !
!                 from which they are generated remain global however as to make    !
!                 them local they would have to be passed through about half of the !
!                 subroutines in the program, or they would have to be read from    !
!                 file repeatedly, which could cause problems in the parallel       !
!                 environment with two threads trying to open the file              !
!                 simultaneously.                                                   !
!      29/01/14 - Altered the outnormpop subroutine so that it outputs the same as  !
!                 the other output subroutine in that it is compatible with         !
!                 multiple PESs. Also made it morecompatible with the adaptive      !
!                 stepsize system and changed the names of the outputsubroutines to !
!                 reflect that one is for static stepsize, one is for adaptive.     !
!      30/01/14 - Moved allocation of mup and muq to the main program from separate !
!                 subroutine, as OpenMP was having trouble allocating in            !
!                 subroutine, even when call was enclosed in a critical block.      !
!      10/02/14 - Included interpolation subroutines for the averaging of data from !
!                 adaptive stepsize propagation system                              !
!      03/03/14 - Included subroutines which carry out simulations using the        !
!                 Harmonic Oscillator Hamiltonian, the Free Particle Hamiltonian    !
!                 and the Morse Oscillator Hamiltonian.                             !
!               - Added switch to allow initial basis set to be a grid              !
!                 (in input.dat) and added a switchboard module (in redirect.f90)   !
!                 which calls the correct Hamiltonian subroutines and functions     !
!                 dependent upon the system being modelled                          !
!               - Included subroutines which output all the wavefunction variable   !
!                 values at each timestep, as well as creating plotting scripts for !
!                 each variable. Similar were also created for the trajectories.    !
!                 These can be disabled easily by commenting.                       !
!      02/04/14 - Completed the encoding of the inverse gaussian system with        !
!                 trajectory reprojection and basis set size adaptation for a       !
!                 static grid.                                                      !
!               - Attempted to implement a Henon-Heiles CCS system, which currently !
!                 does not work                                                     !
!               - Repaired the problem causing incorrect results to be generated by !
!                 the MCEv1 equations.                                              !
!      14/04/14 - Modified the basis set reading system, allowing it to read data   !
!                 from a file and convert it for use by either MCE system or CCS    !
!                 also                                                              !
!               - Confirmed thatRep the MCEv2 system is functioning properly, and   !
!                 that the discrepency with the results for the Spin Boson model are!
!                 a result of the lower coupling between the coherent states and not!
!                 a programming error.                                              !
!      25/09/14 - Finished 3D Grid system and repaired MCEv1 which was damaged      !
!                 during debugging                                                  !
!      30/09/14 - Repaired the Hennon-Heiles system                                 !
!      19/02/15 - Cloning has been added and fully implemented                      !
!               - Repaired trains which were not properly calculating the initial   !
!                 basis, specifically the single configuration amplitudes           !
!               - Fixed the problem that was causing some numerical inconsistencies !
!                 in the spin boson model                                           !
!               - Extended grids and grid-swarms to 3D, and confirmed that it can   !
!                 calculate the inverted gaussian in 3D                             !
!               - Included the 3D Coulomb Potential                                 !
!               - Set functionality to allow starting at t=/=0 when using an input  !
!                 set, and also set output of the basis set at each timestep        !
!      04/03/15 - Repaired the adaptive timestep and openMP systems, which now work !
!                 fully.                                                            !
!               - Repaired the Coulomb potential, which was not being properly      !
!                 calculated                                                        !
!               - Changed the running scripts to allow for use of make to compile   !
!               - Ensured that the program works properly for all model potentials  !
!                                                                                   !
!      Further changelog can be found in the commit statements from the git repo    !
!                                                                                   !
!***********************************************************************************!

  use bsetgen    ! basis set generation module
  use bsetalter  ! module to change the size/position of the basis set
  use Ham        ! General hamiltonian module, inc. overlap calculations etc
  use globvars   ! Global variables, used in all modules
  use readpars   ! Module to read parameters from input file
  use outputs    ! Module to output data
  use alarrays   ! Array allocation module for defined types
  use Chks       ! A set of checks which ensure the program is running correctly
  use propMCE    ! The time propagation controller
  use redirect   ! Module which directs functions to the system specific variants
  use clonecondense ! Module which recombines clones for MCEv1


  implicit none
  !Private variables
  type(basisfn), dimension (:), allocatable :: bset
  type(basisfn), dimension (:), allocatable :: dummybs
  type(basisset), dimension (:), allocatable :: bsetarr
  type(basisset):: testset
  complex(kind=8), dimension (:,:), allocatable :: initgrid, ovrlp,ovrlphold
  complex(kind=8)::normtemp, norm2temp, ehren, acft, extmp
  real(kind=8), dimension(:), allocatable :: mup, muq, popt
  real(kind=8) :: nrmtmp, nrm2tmp, ehrtmp, gridsp, timestrt_loc, normar, brforce, popdiff
  real(kind=8) :: timeend_loc, timeold, time, dt, dtnext, dtdone, initehr, nctmnd, ctime
  real(kind=8) :: initnorm, initnorm2, alcmprss, dum_re1, dum_re2, rescale, pophold1,pophold2 
  integer, dimension(:), allocatable :: clone, clonenum, clonehere
  integer :: j, k, r, y, x, m,nbf, recalcs, conjrep, restart, reps, trspace, v1clonenum, ovrlpout, num_events,two_to_num_events
  integer :: ierr, timestpunit, stepback, dum_in1, dum_in2, dum_in3, finbf, v1check,loop, e, l, nclones, p
  character(LEN=3):: rep
  integer :: clone_instance, range, g, a, b, brunit
  type(basisfn), dimension(:), allocatable ::clone1, clone2
  real, dimension(:,:), allocatable :: populations, ctarray, normpfs
  real(kind=8) ::  crossterm1, crossterm2

  !Reduction Variables
  complex(kind=8), dimension (:), allocatable :: acf_t, extra
  real(kind=8), dimension (:,:), allocatable :: pops
  real(kind=8), dimension(:), allocatable :: absnorm, absnorm2, absehr

  !Public Variables
  real(kind=8), dimension(:), allocatable :: t
  real(kind=8) :: starttime, stoptime, up, down, runtime
  real(kind=8) :: num1, num2, hc
  integer, dimension(:), allocatable :: cloneblock
  integer(kind=8) :: ranseed
  integer:: tnum, cols, genflg, istat, intvl, rprj, n, nsame, nchange, rerun, clonememflg, h
  character(LEN=100) :: LINE, CWD
  character(LEN=1) :: genloc
  integer(kind=4)  :: cnum_start, repchanger, newrep, resnum, norestart, tf, te, orgreps, nbfv1

  call CPU_TIME(starttime) !used to calculate the runtime, which is output at the end

  write(6,"(a)") " ________________________________________________________________ "
  write(6,"(a)") "|                                                                |"
  write(6,"(a)") "|                                                                |"
  write(6,"(a)") "|                  MCE Simulation Program v1.02                  |"
  write(6,"(a)") "|                                                                |"
  write(6,"(a)") "|________________________________________________________________|"
  write(6,"(a)") ""
  write(6,"(a)") ""
  write(6,"(a)") ""

  call initialise        ! this subroutine writes initial values to global variables

  call readrunconds      ! reads the running conditions

  open(unit=570, file="/dev/urandom", access="stream", &
    form="unformatted", action="read", status="old", iostat=istat)
  if (istat == 0) then
    read(570) ranseed    ! This takes the random seed from the true-random bin. If
    close(570)           ! the urandom bin does not exist the random seed is set
  else                   ! to zero which forces the date to be used
    ranseed=0
  end if

  ranseed = abs(ranseed)    ! Negative seed values seem to cause instability

  call ZBQLINI(ranseed,0)   ! Generates the seed value using the UCL random library

  call readbsparams         ! These subroutines read the global parameters used for
  call readzparams          ! basis set generation and propagation.The subroutines
  call readsys              ! are set up to be application independent at this level,
  call readecut             ! with application dependent features included at a lower
  call readtimepar          ! levels.
  call checkparams

  if (step=="S") then       ! Static stepsize case.
    tnum = int(abs(((timeend-timestrt)/dtinit)+0.5)) + 2
  else
    tnum = 1            ! The arrays need to be allocated for reduction in omp
  end if
  
  allocate (pops(tnum,npes), stat=istat)               ! Output arrays are allocated
  if (istat==0) allocate (absehr(tnum), stat=istat)    ! for the number of steps to
  if (istat==0) allocate (absnorm(tnum), stat=istat)   ! be taken
  if (istat==0) allocate (absnorm2(tnum), stat=istat)
  if (istat==0) allocate (acf_t(tnum), stat=istat)
  if (istat==0) allocate (extra(tnum), stat=istat)
  if (istat/=0) then
    write(0,"(a)") "Error in allocating the output matrices for static stepsizes"
    errorflag=1
  end if



  pops = 0.0d0          ! Populations in different quantum states
  absehr = 0.0d0        ! Absolute sum of Ehrenfest Hamiltonian over all bfs
  absnorm = 0.0d0       ! Absolute value of the norm calculated over all bfs
  absnorm2 = 0.0d0      ! Absolute value of the sum of the single config. norms
  acf_t = (0.0d0,0.0d0) ! Auto-correlation function
  extra = (0.0d0,0.0d0)
  v1clonenum = 0.d0
  
  

  if (conjflg==1) then    ! This statement ensures that if conjugate repetition
    intvl = 2             ! is selected the outer repetition loop will increase
  else                    ! by the correct amount without loosing track of the
    intvl = 1             ! number of repetitions.
  end if

  nchange=0
  nsame=0
  rprj=10
  genflg=0
  clonememflg=0
  nbfv1 = in_nbf
  resnum=0
  h=1
  ovrlpout=100


  if (cloneflg=='V1') then
    if (auto_clone=='NO') then 
      if (mod(tnum-2,clone_block).eq.0) then
        num_events = int((tnum-2)/clone_block- 1) 
        write(6,*) 'num of events ', num_events
      else 
        num_events = int((tnum-2)/clone_block) 
        write(6,*) 'num of events ', num_events
      end if 
      num_events = 2
      allocate(cloneblock(num_events+1))
      ! do n =1, size(cloneblock)-1
      !     cloneblock(n) = n*clone_block
      ! end do
      cloneblock(1) = 19
      cloneblock(2) = 210
      ! cloneblock(3) = 63 
      ! cloneblock(4) = 84
      ! cloneblock(5) = 370
      ! cloneblock(6) = 450
      ! cloneblock(7) = 550
      ! cloneblock(8) = 810
      cloneblock(num_events+1) = tnum-2
      two_to_num_events=int(2**num_events)
      call allocbs_alt(bsetarr,two_to_num_events,in_nbf) !allocate(bsetarr(2**num_events,clonefreq))
    else
      write(6,*) clonemax
      call allocbs_alt(bsetarr,2**clonemax,in_nbf) !allocate(bsetarr(2**num_events,clonefreq))
    
    end if 
  end if
 
  

  ! The variables set as private in the below statement are duplicated when Open MP
  ! is run such that there exists individual copies on each thread. The reduction
  ! variables are summed over all threads. The reduction variables are only used in
  ! the static stepsize system as the array size must be known beforehand to avoid
  ! memory leaks.

  !$omp parallel private (bset, dummybs, initgrid, ovrlp, normtemp,&
  !$omp                    norm2temp, ehren, acft, extmp, muq, mup, popt,  &
  !$omp                    nrmtmp, nrm2tmp, ehrtmp, gridsp, timestrt_loc, trspace,                &
  !$omp                    timeend_loc, timeold, time, dt, dtnext, dtdone, initehr,               &
  !$omp                    initnorm, initnorm2, alcmprss, clone, clonenum, bsetarr, popdiff,      &
  !$omp                    j, k, r, y, x, m, nbf, recalcs, conjrep, restart, brforce,             &
  !$omp                    reps, ierr, timestpunit, stepback, dum_in1, dum_in2, clonehere,        &
  !$omp                    finbf, dum_in3, dum_re1, dum_re2, rep, genloc, h, clone_instance,      &
  !$omp                    nclones, clone1, clone2, populations, ctarray, normpfs,                &
  !$omp                    range, rescale, i, p, g, clonememflg, e, ovrlphold                     )

  !$omp do reduction (+:acf_t, extra, pops, absnorm, absnorm2, absehr)

  ! This leaves the following variables currently shared actross all threads:
  ! p, q, t, starttime, stoptime, up, down, runtime, num1, num2, ranseed, tnum,
  ! cols, genflg, istat, intvl, rprj, n, nsame, nchange, LINE, CWD
  do k=1,reptot,intvl              ! Loop over all repeats.
    call flush(6)
    call flush(0)

    if (errorflag .ne. 0) cycle   ! errorflag is the running error catching system

    ierr = 0
    conjrep = 1
    genloc = gen
    restart=0
    trspace = trainsp
    hc=0.d0
    clonememflg=0
    nclones = 1
  
  
    
    e=1
    

    if (restrtflg==1) then
      call restartnum(k,genloc,restart)
      if (restart==1) then
        cycle
      end if
    end if
    

    allocate (popt(npes), stat=ierr)
    if (ierr/=0) then
      write(0,"(a)") "Error in allocating the temporary population array in Main"
      errorflag=1
    end if
    popt = 0.0d0

    if (genloc.eq."Y") then
      allocate (mup(ndim), stat=ierr)
      if (ierr == 0) allocate (muq(ndim), stat=ierr)
      if (ierr/=0) then
        write(0,"(a)") "Error in allocation of mup and muq"
        errorflag=1
      end if
      mup = 0.0d0
      muq = 0.0d0
    end if

    do while (conjrep .lt. 3) ! conjugate repetitions. If equal to 3 then both
                              ! have been completed.
      alcmprss = 1.0d0/initalcmprss    ! initialcmprss is the value read from the
      gridsp=initsp                    ! input file. For automatic adaptation of
      nbf=in_nbf                       ! the compression parameter this is used
      recalcs=0                        ! as a starting point, otherwise it is used
      x=0                              ! as the compression parameter value

      if (conjrep == 2) then         ! this conditional and the subsequent keeps
        reps=k+1                     ! track of the repeats with regard to the
      else if (conjrep == 1) then    ! conjugate repeat system
        reps=k
      else
        errorflag=1
      end if
      
      if (conjflg==1) then
        conjrep = conjrep + 1
      else
        conjrep = 3
      end if
      
      time = timestrt         ! It is possible to start at t=/=0, but
      timestrt_loc = timestrt ! precalculated basis should be used
  

      !**********Basis Set Generation Section Begins**************************!

      if (genloc.eq."Y") then     ! begin the basis set generation section.

        restart = 1            ! a flag for if the basis set needs recalculating

        


        if (conjflg==1) then
          if (conjrep == 2) then         ! first/only calculation
            !$omp critical               ! Critical block stops subroutine running on
            call genzinit(mup, muq,reps) ! multiple threads simultaneously, needed as
            !$omp end critical           ! the UCL random library is not thread safe
          else
            do m=1,ndim
              mup(m) = -1.0d0*mup(m)  ! second calculation takes the conj. of z_init
            end do
          end if
        else
          !$omp critical
          call genzinit(mup, muq,reps)
          !$omp end critical
        end if

        do while ((restart.eq.1).and.(recalcs.lt.Ntries).and.(alcmprss.gt.1.0d-5))

          restart = 0    ! if restart stays as 0, the basis set is not recalculated

          call allocbs(bset, nbf)

          !$omp critical             ! Critical block needed for random number gen.
          call genbasis(bset, mup, muq, alcmprss, time, reps, trspace)

          call genD_big(bset, mup, muq, restart) !Generates the multi config D
                                      !prefactor and single config a & d prefactors
                                      ! Moved to inside the genbasis sunbbroutines
          !$omp end critical

          initnorm = 0.0d0
          initnorm2 = 0.0d0

          ! Checks norms and population sum to ensure basis set is calculated
          ! properly. If not, restart is set to 1 so basis is recalculated

          call initnormchk(bset,recalcs,restart,alcmprss,initnorm,initnorm2,trspace)

!!!!!!! Block to force renormalisation. Use with caution !!!!!!!!!!!!!!

!          if (restart.eq.1) then
!            if ((((conjflg==1).and.(conjrep.eq.2)).or.(conjflg/=1)).and.(recalcs.lt.Ntries)) then
!              !$omp critical
!              call genzinit(mup, muq,reps)
!              !$omp end critical
!            else
!              do j=1,size(bset)
!                bset(j)%D_big = bset(j)%D_big/sqrt(initnorm)
!              end do
!              write(6,"(a,e16.8e3)") "Renormalising! Old norm was ", initnorm
!              call initnormchk(bset, recalcs, restart,alcmprss, gridsp, initnorm, initnorm2)
!              write(6,"(a,e16.8e3)") "               New norm is  ", initnorm
!              recalcs = recalcs - 1
!              restart = 0
!            end if
!          end if

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

          if ((restart.eq.1).and.(recalcs.lt.Ntries)) then
            call deallocbs(bset)                            !Before recalculation, the basis must be deallocated
            write(6,"(a,i0,a,i0)") "Attempt ", recalcs, " of ", Ntries
          end if

          call flush(6)
          call flush(0)

        end do   !End of basis set recalculation loop.

        if ((restart.eq.1).and.(recalcs.ge.Ntries)) then   ! Fatal error
          write(0,"(a,i0,a)") "Initial Basis Set Error. Not resolved after ", recalcs, " repeat calculations."
          write(6,"(a)")"TERMINATING PROGRAM"
          stop
        end if

        if ((restart.eq.1).and.(alcmprss.le.1.0d-5).and.(cmprss.eq."Y")) then   ! Fatal error
          write(0,"(a)") "Initial Basis Set Error. Not resolved after reducing compression parameter to 1.0d-5."
          write(0,"(a)") "Probable Error in Code"
          write(0,"(a)") " "
          write(6,"(a)") "TERMINATING PROGRAM"
          stop
        end if

        if (((method=="MCEv2").or.(method=="MCE1")).and.((cloneflg=="BLIND").or.(cloneflg=="BLIND+"))) then
          write(rep,"(i3.3)") reps
          open(unit=47756,file="Clonetrack-"//trim(rep)//".out",status="new",iostat=ierr)
          close(47756)
          allocate (clone(nbf), stat=ierr)
          if (ierr==0) allocate(clonenum(nbf), stat=ierr)
          if (ierr/=0) then
            write(0,"(a)") "Error in allocating clone arrays"
            errorflag = 1
          end if
          if (genloc=="N") then
            call readclone(clonenum, reps, clone)
          else
            do j=1,nbf
              clone(j) = 0
              clonenum(j) = 0
            end do
          end if
          write (6,'(a)') "Blind cloning arrays generated and cloning starting"
          call flush(6)
          call cloning (bset, nbf, x, time, clone, clonenum, reps)
          call flush(6)
        end if

        if (errorflag.eq.0) then  ! Only executes if generation is successful
          write(6,"(a)") "Basis Set Generated Successfully"
          write(6,"(a,e15.8)") "Abs(Norm) = ", initnorm
          if (npes.ne.1) write(6,"(a,e15.8)") "Popsum    = ", initnorm2
          if ((cmprss.eq."Y").and.((basis.eq."SWARM").or.(basis.eq."SWTRN"))) write(6,"(a,e15.8)") "Alcmprss  = ", 1.0d0/alcmprss
          if ((cmprss.eq."Y").and.(basis.eq."SWTRN")) write(6,"(a,i0)") "Train Spacing  = ", trspace
        else
          write(6,"(a)") "Errors found in basis set generation"
          call outbs(bset, reps, mup, muq, time,0)
          call flush(6)
          stop
        end if
        
        if (prop.eq."N") then
          call outbs(bset, reps, mup, muq, time,0)
        end if

      end if !End of Basis set generation conditional statement

      !*************Basis Set Propagation Section Begins*************************!

      if (prop.eq."Y") then     ! Propagation of basis set

        x=0
        timeend_loc = timeend

        if (genloc.eq."N") then
          !$omp critical                       !Critical block to stop inputs getting confused
          if (conjrep == 2) then               ! Stops it looking for a basis set file if conjugate repetition selected
            write(0,"(a)") "Propagation only selected with conjugate repeats enabled."
            write(0,"(a)") "This error message should not ever be seen, and means something's corrupted"
            errorflag=1                       ! as these two conditions are incompatible and should be disallowed at
          else                                ! the run conditions input stage.
            call allocbs(bset,nbf)
            call readbasis(bset, mup, muq, reps, time, nbf) ! reads and assigns the basis set parameters and values, ready for propagation.
            timestrt_loc=time
            if((cloneflg.eq."V1").and.(loop>0))then 
              time=time+dtinit
            end if
            write(6,"(a,i0,a)") "Starting from previous file. ", &
                        int(real(abs((timeend_loc-timestrt_loc)/dtinit))), " steps remaining."
          end if
          !$omp end critical
        end if

        dt = dtinit                ! The value read from the input stage. In adaptive step theis changes

        !The initial values of the output parameters are calculated here.

        allocate(ovrlp(size(bset),size(bset)))
        ovrlp=ovrlpmat(bset)
        normtemp = norm(bset,ovrlp)
        initnorm = sqrt(dble(normtemp*dconjg(normtemp)))
        nrmtmp = initnorm
        ehren = (0.0d0, 0.0d0)
        if (method=="MCEv2") then    ! the single configurational wavefunction is only normalised for MCEv2
          norm2temp = norm2(bset)
          initnorm2 = sqrt(dble(norm2temp*dconjg(norm2temp)))
        end if
        do j = 1,nbf
          ehren = ehren + HEhr(bset(j), time, reps)
        end do
        initehr = abs(ehren)
        acft = acf(bset,mup,muq)
        call extras(extmp, bset)
        do r=1,npes
          popt(r) = pop(bset, r,ovrlp)
        end do
        if (step == "S") then        ! Output parameters only written to arrays if static stepsize
          do r=1,npes
            pops(1,r) = pops(1,r) + popt(r)
          end do
          absehr(1) = absehr(1) + initehr
          absnorm(1) = absnorm(1) + initnorm
          if (method=="MCEv2") absnorm2(1) = absnorm2(1) + initnorm2
          acf_t(1) = acf_t(1) + acft
          extra(1) = extra(1) + extmp
          call outnormpopadapheads(reps)
          call outnormpopadap(initnorm,acft,extmp,initehr,popt,x,reps,time)
        else                         ! For adaptive stepsize the data is output straight away
          timestpunit=1710+reps
          write(rep,"(i3.3)") reps
          open (unit=timestpunit,file="timesteps-"//trim(rep)//".out",status="unknown",iostat=istat)
          close (timestpunit)
          call outnormpopadapheads(reps)
          call outnormpopadap(initnorm,acft,extmp,initehr,popt,x,reps,time)
        end if
        deallocate(ovrlp)

        !***********Timesteps***********!
       
        if (((method=="MCEv2").or.(method=="MCEv1")).and.((cloneflg=="YES").or.(cloneflg=="QSC"))) then
          write(rep,"(i3.3)") reps
          open(unit=47756,file="Clonetrack-"//trim(rep)//".out",status="new",iostat=ierr)
          close(47756)
          allocate (clone(nbf), stat=ierr)
          if (ierr==0) allocate(clonenum(nbf), stat=ierr)
          if (ierr/=0) then
            write(0,"(a)") "Error in allocating clone arrays"
            errorflag = 1
          end if
          if (genloc=="N") then
            call readclone(clonenum, reps, clone)
          else
            do j=1,nbf
              clone(j) = 0
              clonenum(j) = 0
            end do
          end if
          write (6,"(a)") "Conditional cloning arrays generated"
        end if

        if (cloneflg=="V1") then
          call bstransfer(bsetarr(1)%bs,bset,nbf)
        end if
        write(6,"(a)") "Beginning Propagation"
        call flush(6)

        do while ((time.lt.timeend_loc).and.(x.le.tnum+2)) !timestep loop 

          if (errorflag .ne. 0) exit
          x = x + 1  ! timestep index
          y = x + 1  ! array index
          call trajchk(bset) !ensures that the position component of the coherent states are not too widely spaced
          call outbs(bset, reps, mup, muq, time,x) 
          
          if (cloneflg=="V1") then 
            do p = 1, nclones 
              call propstep (bsetarr(p)%bs, dt, dtnext, dtdone, time, genflg, timestrt_loc,x,reps)     ! Takes a single timestep
            end do 

            call v1cloning_check(bsetarr, cloneblock, e, nbf, nclones,x)
         
            if (dtdone.eq.dt) then   ! nsame and nchange are used to keep track of changes to the stepsize.
              !$omp atomic           !atomic parameter used to ensure two threads do not write to the same
              nsame = nsame + 1      !memory address simultaneously as these counts are taken over all repeats.
            else
              !$omp atomic
              nchange = nchange + 1
            end if
            if (abs(time+dtdone-timeend_loc).le.1.0d-10) then   ! if time is close enough to end time, set as end time
              time=timeend_loc
            else
              time = time + dtdone                         ! increment time
            end if
            dt = dtnext      ! dtnext is set by the adaptive step size system. If static, dtnext = dt already

            if (nclones.gt.1) then 
              call alt_clone_condense(bsetarr,dt,x,reps,nclones,nbf,absnorm,acf_t,extra,absehr, pops, mup, muq, time)
            else 
              call postprop(bsetarr(1)%bs,nbf,x,y,reps,muq,mup,time,popt,pops,timestrt_loc,timeend_loc,dt,absehr, &
                absnorm,absnorm2,acf_t,extra)
            end if
          else if (cloneflg.ne."V1") then
            write(6,*) x
            call propstep (bset, dt, dtnext, dtdone, time, genflg, timestrt_loc,x,reps)     ! This subroutine takes a single timestep

            if (dtdone.eq.dt) then   ! nsame and nchange are used to keep track of changes to the stepsize.
              !$omp atomic           !atomic parameter used to ensure two threads do not write to the same
              nsame = nsame + 1      !memory address simultaneously as these counts are taken over all repeats.
            else
              !$omp atomic
              nchange = nchange + 1
            end if
            
            if (abs(time+dtdone-timeend_loc).le.1.0d-10) then   ! if time is close enough to end time, set as end time
              time=timeend_loc
            else
              time = time + dtdone                         ! increment time
            end if
          
            ! if cloning and at a point of cloning, copy the information over to another 
            ! **************************************************************************
            
            dt = dtnext      ! dtnext is set by the adaptive step size system. If static, dtnext = dt already

            ! output variables written to arrays. Note - if a non-fatal error flag is implemented (currently only fatal errors implemented),
            ! the outputs will have to be saved over the course of propagation and then added to the main arrays at time==timeend


            te = int(real(abs((timeend_loc-timestrt_loc)/dt)))

            
          
            if ((allocated(clone)).and.(cloneflg.ne."BLIND").and.(time.le.timeend).and.(cloneflg.ne."V1")) then
              call cloning (bset, nbf, x, time, clone, clonenum, reps)
            end if

            call postprop(bset,nbf,x,y,reps,muq,mup,time,popt,pops,timestrt_loc,timeend_loc,dt,absehr, &
              absnorm,absnorm2,acf_t,extra)
            write(6,*) 'one timestep done'
          end if

        end do   !End of time propagation.
        write(6,*)'end of time propagation'


        if ((time.lt.timeend).and.(errorflag.ne.1)) then
          write(0,"(a,e12.5)") "Too many steps taken. Propagation aborted at t = ", time
          write(0,"(a)") "Consider revising timestep parameters"
        end if

        if (allocated(clone)) then
          deallocate (clone, stat=ierr)
          if (ierr==0) deallocate(clonenum, stat=ierr)
          if (ierr/=0) then
            write(0,"(a)") "Error in deallocating clone arrays"
            errorflag = 1
          end if
        end if
     
      end if

      if (errorflag==1) then
        write(6,"(a)") "Last basis set outputting...."
        call outbs(bset, reps, mup, muq, time, x)
      end if
  
      call deallocbs(bset)     ! Deallocates basis set ready for next repeat



      if ((conjrep==2).and.(errorflag==0)) then
        write(6,"(a)") "Starting Conjugate propagation"
      else
        exit
      end if

      call flush(6)
      call flush(0)
      
    end do !conjugate repeat
    if (allocated(mup)) deallocate (mup, stat=ierr)
    if ((allocated(muq)).and.(ierr==0)) deallocate (muq, stat=ierr)
    if ((allocated(popt)).and.(ierr==0)) deallocate (popt, stat=ierr)

    if (ierr/=0) then
      write(0,"(a,i0)") "Error deallocating mup, muq or popt in repeat ", reps
      errorflag=1
    end if
    call flush(6)
    call flush(0)

  
    
  end do ! The main repeat loop
  !$omp end do
  !$omp end parallel
  

  write(6,"(a)") "Finished Propagation"
  
  if (prop=="Y") then
    if ((step=="S").and.(errorflag==0)) then    !Outputs data to file
      pops = pops/dble(reptot)
      absehr = absehr/dble(reptot)
      absnorm = 1
      if (method=="MCEv2") absnorm2 = absnorm2/dble(reptot)
      acf_t = acf_t/dble(reptot)
      extra = extra/dble(reptot)
      call outnormpopstat(absnorm, acf_t, extra, absehr, pops)
      deallocate(absnorm,absnorm2,acf_t,absehr,extra,pops,stat = istat)
      if (istat/=0) then
        write(0,"(a)") "Error in deallocation of output arrays in main"
        errorflag=1
      end if
    else if ((step=="A").and.(errorflag==0)) then   ! builds a histogram of data
      call system ("cat timesteps-* > timesteps.out")
      open (unit=1710,file="timesteps.out",status="old",iostat=istat)
      if (istat.ne.0) then
        write(0,"(a)") "Error opening the compined timesteps file"
      else
        istat=0
        n=0
        do while (istat==0)
          read (1710,"(a)",iostat=istat) LINE
          n=n+1
        end do
        n=n-1
        write(6,"(a,i0)") "size of timestep array is ", n
        rewind(1710)
        allocate(t(n), stat = istat)
        if (istat/=0) then
          write(0,"(a)") "Error in timestep array allocation"
          errorflag=1
        end if
        do k=1,n
          read (1710,"(e12.5)",iostat=istat) t(k)
          if (istat/=0) t(k) = 0.0d0
        end do
        close(1710)
        num1 = maxval(t)
        num2 = minval(t)
        write(6,"(a,f15.8)") "maxval of timestep array is ", num1
        write(6,"(a,f15.8)") "minval of timestep array is ", num2
        up=0.0
        down=0.0
        call histogram(t,n,"timehist.out",up,down)
        deallocate(t, stat = istat)
        if (istat/=0) then
          write(0,"(a)") "Error in timestep array deallocation"
          errorflag=1
        end if
        if (npes==2) then
          cols=13
        else
          cols=10+npes
        end if
        call interpolate(cols,errorflag)
      end if
    end if
  end if

  if (errorflag .ne. 0) then
    write(6,"(a)") "Program terminated early."
    write(6,"(a,i0)") "errorflag value is ", errorflag
  end if

  call CPU_TIME(stoptime)
  runtime = stoptime-starttime
  call getcwd(CWD)

  if (errorflag.eq.0) write(6,"(a,a)") 'Successfully Executed MCE Program in ', trim(CWD)
  if (errorflag.ne.0) write(6,"(a,a)") 'Unsuccessfully Executed MCE Program in ', trim(CWD)
  if (step == "A") then
    write(6,"(a,i0,a,i0,a)") 'Of ', nsame + nchange, ' steps, ', nchange, ' were changed'
  end if
  if (runtime/3600.0d0 .gt. 1.0d0)then
    runtime = runtime/3600.0d0
    write(6,"(a,es12.5,a)") 'Time taken : ', runtime, ' hours'
  else if (runtime/60.0d0 .gt. 1.0d0)then
    runtime = runtime/60.0d0
    write(6,"(a,es12.5,a)") 'Time taken : ', runtime , ' mins'
  else
    write(6,"(a,es12.5,a)") 'Time taken : ', runtime, ' seconds'
  end if
  

  call flush(6)
  call flush(0)

  stop

end program MainMCE
