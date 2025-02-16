! common PRIME2D/PRIME3D routines used primarily by the Hadamard matchers
module simple_strategy2D3D_common
include 'simple_lib.f08'
use simple_image,      only: image
use simple_cmdline,    only: cmdline
use simple_builder,    only: build_glob
use simple_parameters, only: params_glob
use simple_stack_io,   only: stack_io
use simple_estimate_ssnr
implicit none

public :: read_imgbatch, set_bp_range, set_bp_range2D, grid_ptcl, prepimg4align,&
&norm_struct_facts, calcrefvolshift_and_mapshifts2ptcls, read_and_filter_refvols,&
&preprefvol, prep2Dref, preprecvols, killrecvols, prepimgbatch
private
#include "simple_local_flags.inc"

interface read_imgbatch
    module procedure read_imgbatch_1
    module procedure read_imgbatch_2
end interface read_imgbatch

real, parameter :: SHTHRESH  = 0.001
real, parameter :: CENTHRESH = 0.5    ! threshold for performing volume/cavg centering in pixels
type(stack_io)  :: stkio_r
logical         :: did_filter

contains

    subroutine read_imgbatch_1( fromptop, ptcl_mask )
        integer,           intent(in) :: fromptop(2)
        logical, optional, intent(in) :: ptcl_mask(params_glob%fromp:params_glob%top)
        character(len=:), allocatable :: stkname
        integer :: iptcl, ind_in_batch, ind_in_stk
        if( present(ptcl_mask) )then
            do iptcl=fromptop(1),fromptop(2)
                if( ptcl_mask(iptcl) )then
                    ind_in_batch = iptcl - fromptop(1) + 1
                    call build_glob%spproj%get_stkname_and_ind(params_glob%oritype, iptcl, stkname, ind_in_stk)
                    if( .not. stkio_r%stk_is_open() )then
                        call stkio_r%open(stkname, params_glob%smpd, 'read')
                    else if( .not. stkio_r%same_stk(stkname, [params_glob%box,params_glob%box,1]) )then
                        call stkio_r%close
                        call stkio_r%open(stkname, params_glob%smpd, 'read')
                    endif
                    call stkio_r%read(ind_in_stk, build_glob%imgbatch(ind_in_batch))
                endif
            end do
            call stkio_r%close
        else
            do iptcl=fromptop(1),fromptop(2)
                ind_in_batch = iptcl - fromptop(1) + 1
                call build_glob%spproj%get_stkname_and_ind(params_glob%oritype, iptcl, stkname, ind_in_stk)
                if( .not. stkio_r%stk_is_open() )then
                    call stkio_r%open(stkname, params_glob%smpd, 'read')
                else if( .not. stkio_r%same_stk(stkname, [params_glob%box,params_glob%box,1]) )then
                    call stkio_r%close
                    call stkio_r%open(stkname, params_glob%smpd, 'read')
                endif
                call stkio_r%read(ind_in_stk, build_glob%imgbatch(ind_in_batch))
            end do
            call stkio_r%close
        endif
    end subroutine read_imgbatch_1

    subroutine read_imgbatch_2( n, pinds, batchlims )
        integer,          intent(in)  :: n, pinds(n), batchlims(2)
        character(len=:), allocatable :: stkname
        integer :: ind_in_stk, i, ii
        do i=batchlims(1),batchlims(2)
            ii = i - batchlims(1) + 1
            call build_glob%spproj%get_stkname_and_ind(params_glob%oritype, pinds(i), stkname, ind_in_stk)
            if( .not. stkio_r%stk_is_open() )then
                call stkio_r%open(stkname, params_glob%smpd, 'read')
            else if( .not. stkio_r%same_stk(stkname, [params_glob%box,params_glob%box,1]) )then
                call stkio_r%close
                call stkio_r%open(stkname, params_glob%smpd, 'read')
            endif
            call stkio_r%read(ind_in_stk, build_glob%imgbatch(ii))
        end do
        call stkio_r%close
    end subroutine read_imgbatch_2

    subroutine set_bp_range( cline )
        class(cmdline), intent(inout) :: cline
        real, allocatable     :: resarr(:), fsc_arr(:)
        real                  :: fsc0143, fsc05
        real                  :: mapres(params_glob%nstates)
        integer               :: s, loc(1), lp_ind, k_nyq
        character(len=STDLEN) :: fsc_fname
        logical               :: fsc_bin_exists(params_glob%nstates), all_fsc_bin_exist
        ! Nyqvist index
        k_nyq = calc_fourier_index(2.*params_glob%smpd, params_glob%box, params_glob%smpd)
        if( params_glob%l_lpset )then
            ! set Fourier index range
            params_glob%kfromto(1) = max(2, calc_fourier_index( params_glob%hp, params_glob%box, params_glob%smpd))
            params_glob%kfromto(2) = calc_fourier_index(params_glob%lp, params_glob%box, params_glob%smpd)
            if( cline%defined('lpstop') )then
                params_glob%kfromto(2) = min(params_glob%kfromto(2),&
                    &calc_fourier_index(params_glob%lpstop, params_glob%box, params_glob%smpd))
            endif
            params_glob%kstop = params_glob%kfromto(2)
            if( params_glob%l_needs_sigma ) params_glob%kfromto(2) = k_nyq
        else
            ! check all fsc_state*.bin exist
            all_fsc_bin_exist = .true.
            fsc_bin_exists    = .false.
            do s=1,params_glob%nstates
                if( params_glob%nstates > 1 )then
                    fsc_fname = trim(CLUSTER3D_FSC)
                else
                    fsc_fname = trim(FSC_FBODY)//int2str_pad(s,2)//BIN_EXT
                endif
                fsc_bin_exists( s ) = file_exists(trim(adjustl(fsc_fname)))
                if( build_glob%spproj_field%get_pop(s, 'state') > 0 .and. .not.fsc_bin_exists(s))&
                    & all_fsc_bin_exist = .false.
            enddo
            if(build_glob%spproj%is_virgin_field(params_glob%oritype)) &
                all_fsc_bin_exist = (count(fsc_bin_exists)==params_glob%nstates)
            ! set low-pass Fourier index limit
            if( all_fsc_bin_exist )then
                resarr = build_glob%img%get_res()
                do s=1,params_glob%nstates
                    if( fsc_bin_exists(s) )then
                        ! these are the 'classical' resolution measures
                        if( params_glob%nstates > 1 )then
                            fsc_fname = trim(CLUSTER3D_FSC) ! mixed model FSC
                        else
                            fsc_fname = trim(FSC_FBODY)//int2str_pad(s,2)//BIN_EXT
                        endif
                        fsc_arr = file2rarr(trim(adjustl(fsc_fname)))
                        build_glob%fsc(s,:) = fsc_arr(:)
                        deallocate(fsc_arr)
                        call get_resolution(build_glob%fsc(s,:), resarr, fsc05, fsc0143)
                        mapres(s) = fsc0143
                    else
                        ! empty state
                        mapres(s)           = 0.
                        build_glob%fsc(s,:) = 0.
                    endif
                end do
                loc = maxloc(mapres) ! worst resolved
                if( params_glob%nstates == 1 )then
                    ! get median updatecnt
                    if( build_glob%spproj_field%median('updatecnt') > 1.0 )then ! more than half have been updated
                        lp_ind = get_lplim_at_corr(build_glob%fsc(1,:), params_glob%lplim_crit)
                    else
                        lp_ind = get_lplim_at_corr(build_glob%fsc(1,:), 0.5) ! more conservative limit @ start
                    endif
                else
                    lp_ind = get_lplim_at_corr(build_glob%fsc(loc(1),:), params_glob%lplim_crit)
                endif
                if( params_glob%cc_objfun == OBJFUN_EUCLID ) lp_ind = min(lp_ind+10,k_nyq) ! relion-like aggressive limit
                ! interpolation limit is NOT Nyqvist in correlation search
                params_glob%kfromto(2) = calc_fourier_index(resarr(lp_ind), params_glob%box, params_glob%smpd)
            else if( build_glob%spproj_field%isthere(params_glob%fromp,'lp') )then
                params_glob%kfromto(2) = calc_fourier_index(&
                    build_glob%spproj_field%get(params_glob%fromp,'lp'), params_glob%box, params_glob%smpd)
            else
                THROW_HARD('no method available for setting the low-pass limit. Need fsc file or lp find; set_bp_range')
            endif
            ! lpstop overrides any other method for setting the low-pass limit
            if( cline%defined('lpstop') )then
                params_glob%kfromto(2) = min(params_glob%kfromto(2), &
                    calc_fourier_index(params_glob%lpstop, params_glob%box, params_glob%smpd))
            endif
            ! low-pass limit equals interpolation limit for correlation search
            params_glob%kstop = params_glob%kfromto(2)
            if( params_glob%l_needs_sigma ) params_glob%kfromto(2) = k_nyq
            ! set high-pass Fourier index limit
            params_glob%kfromto(1) = max(2,calc_fourier_index( params_glob%hp, params_glob%box, params_glob%smpd))
            ! re-set the low-pass limit
            params_glob%lp = calc_lowpass_lim(params_glob%kstop, params_glob%box, params_glob%smpd)
        endif
        call build_glob%spproj_field%set_all2single('lp',params_glob%lp)
    end subroutine set_bp_range

    subroutine set_bp_range2D( cline, which_iter, frac_srch_space )
        class(cmdline), intent(inout) :: cline
        integer,        intent(in)    :: which_iter
        real,           intent(in)    :: frac_srch_space
        real    :: lplim
        integer :: lpstart_find, k_nyq
        ! Nyqvist index
        k_nyq = calc_fourier_index(2.*params_glob%smpd, params_glob%box, params_glob%smpd)
        ! High-pass index
        params_glob%kfromto(1) = max(2, calc_fourier_index(params_glob%hp, params_glob%box, params_glob%smpd))
        if( params_glob%l_lpset )then
            lplim = params_glob%lp
            params_glob%kfromto(2) = calc_fourier_index(lplim, params_glob%box, params_glob%smpd)
        else
            if( file_exists(params_glob%frcs) .and. which_iter >= LPLIM1ITERBOUND )then
                lplim = build_glob%clsfrcs%estimate_lp_for_align()
            else
                if( which_iter < LPLIM1ITERBOUND )then
                    lplim = params_glob%lplims2D(1)
                else if( frac_srch_space >= FRAC_SH_LIM .and. which_iter > LPLIM3ITERBOUND )then
                    lplim = params_glob%lplims2D(3)
                else
                    lplim = params_glob%lplims2D(2)
                endif
            endif
            params_glob%kfromto(2) = calc_fourier_index(lplim, params_glob%box, params_glob%smpd)
            ! to avoid pathological cases, fall-back on lpstart
            lpstart_find = calc_fourier_index(params_glob%lpstart, params_glob%box, params_glob%smpd)
            if( lpstart_find > params_glob%kfromto(2) ) params_glob%kfromto(2) = lpstart_find
        endif
        params_glob%kstop = params_glob%kfromto(2)
        if( params_glob%l_needs_sigma ) params_glob%kfromto(2) = k_nyq
        call build_glob%spproj_field%set_all2single('lp',lplim)
    end subroutine set_bp_range2D

    !>  \brief  grids one particle image to the volume
    subroutine grid_ptcl( fpl, se, o )
        use simple_fplane, only: fplane
        use simple_sym,    only: sym
        use simple_ori,    only: ori
        class(fplane),   intent(in) :: fpl
        class(sym),      intent(inout) :: se
        class(ori),      intent(inout) :: o
        real      :: pw
        integer   :: s, eo
        ! state flag
        s = o%get_state()
        if( s == 0 ) return
        ! eo flag
        eo = nint(o%get('eo'))
        ! particle-weight
        pw = 1.0
        if( o%isthere('w') ) pw = o%get('w')
        if( pw > TINY ) call build_glob%eorecvols(s)%grid_plane(se, o, fpl, eo, pwght=pw)
    end subroutine grid_ptcl

    !>  \brief  prepares one particle image for alignment
    !!          serial routine
    subroutine prepimg4align( iptcl, img_in, img_out )
        use simple_polarizer,     only: polarizer
        use simple_ctf,           only: ctf
        integer,          intent(in)    :: iptcl
        class(image),     intent(inout) :: img_in
        class(polarizer), intent(inout) :: img_out
        type(ctf)       :: tfun
        type(ctfparams) :: ctfparms
        real            :: x, y, sdev_noise
        x = build_glob%spproj_field%get(iptcl, 'x')
        y = build_glob%spproj_field%get(iptcl, 'y')
        ! CTF parameters
        ctfparms = build_glob%spproj%get_ctfparams(params_glob%oritype, iptcl)
        ! normalise
        call img_in%noise_norm(build_glob%lmsk, sdev_noise)
        ! move to Fourier space
        call img_in%fft()
        ! Shift image to rotational origin & phase-flipping
        if(abs(x) > SHTHRESH .or. abs(y) > SHTHRESH) call img_in%shift2Dserial([-x,-y])
        select case(ctfparms%ctfflag)
            case(CTFFLAG_NO, CTFFLAG_FLIP)
                ! all good
            case(CTFFLAG_YES) ! phase flip
                tfun = ctf(ctfparms%smpd, ctfparms%kv, ctfparms%cs, ctfparms%fraca)
                call tfun%apply_serial(img_in, 'flip', ctfparms)
            case DEFAULT
                THROW_HARD('unsupported CTF flag: '//int2str(ctfparms%ctfflag)//' prepimg4align')
        end select
        ! back to real-space
        call img_in%ifft()
        ! clip image if needed
        call img_in%clip(img_out)
        ! soft-edged mask
        if( params_glob%l_focusmsk )then
            call img_out%mask(params_glob%focusmsk, 'soft')
        else
            if( params_glob%l_needs_sigma )then
                call img_out%mask(params_glob%msk, 'softavg')
            else
                call img_out%mask(params_glob%msk, 'soft')
            endif
        endif
        ! gridding prep
        if( params_glob%gridding.eq.'yes' ) call img_out%div_by_instrfun
        ! return in Fourier space
        call img_out%fft()
    end subroutine prepimg4align

    !>  \brief  prepares one cluster centre image for alignment
    subroutine prep2Dref( pftcc, img_in, img_out, icls, center, xyz_in, xyz_out )
        use simple_polarft_corrcalc, only: polarft_corrcalc
        use simple_polarizer,        only: polarizer
        class(polarft_corrcalc), intent(inout) :: pftcc
        class(image),            intent(inout) :: img_in
        class(polarizer),        intent(inout) :: img_out
        integer,                 intent(in)    :: icls
        logical, optional,       intent(in)    :: center
        real,    optional,       intent(in)    :: xyz_in(3)
        real,    optional,       intent(out)   :: xyz_out(3)
        integer :: filtsz
        real    :: frc(build_glob%img%get_filtsz()), filter(build_glob%img%get_filtsz())
        real    :: xyz(3), sharg
        logical :: do_center
        filtsz = build_glob%img%get_filtsz()
        do_center = (params_glob%center .eq. 'yes')
        ! centering only performed if params_glob%center.eq.'yes'
        if( present(center) ) do_center = do_center .and. center
        if( do_center )then
            if( present(xyz_in) )then
                sharg = arg(xyz_in)
                if( sharg > CENTHRESH )then
                    ! apply shift and do NOT update the corresponding class parameters
                    call img_in%fft()
                    call img_in%shift2Dserial(xyz_in(1:2))
                endif
            else
                xyz = img_in%calc_shiftcen_serial(params_glob%cenlp, params_glob%msk)
                sharg = arg(xyz)
                if( sharg > CENTHRESH )then
                    ! apply shift and update the corresponding class parameters
                    call img_in%fft()
                    call img_in%shift2Dserial(xyz(1:2))
                    call build_glob%spproj_field%add_shift2class(icls, -xyz(1:2))
                endif
                if( present(xyz_out) ) xyz_out = xyz
            endif
        endif
        ! filter (filtering and masking only done if params_glob%l_opt_filter == .false.)
        if( .not. params_glob%l_opt_filter )then
            call build_glob%clsfrcs%frc_getter(icls, params_glob%hpind_fsc, params_glob%l_phaseplate, frc)
            if( any(frc > 0.143) )then
                call fsc2optlp_sub(filtsz, frc, filter)
                if( params_glob%l_match_filt )then
                    call pftcc%set_ref_optlp(icls, filter(params_glob%kfromto(1):params_glob%kstop))
                else
                    call img_in%fft() ! needs to be here in case the shift was never applied (above)
                    call img_in%apply_filter_serial(filter)
                endif
            endif
        endif
        ! ensure we are in real-space
        call img_in%ifft()
        ! clip image if needed
        call img_in%clip(img_out)
        ! apply mask
        call img_out%mask(params_glob%msk, 'soft')
        ! gridding prep
        if( params_glob%gridding.eq.'yes' ) call img_out%div_by_instrfun
        ! move to Fourier space
        call img_out%fft()
    end subroutine prep2Dref

    !>  \brief  initializes all volumes for reconstruction
    subroutine preprecvols( wcluster )
        real, optional, intent(in)    :: wcluster
        character(len=:), allocatable :: part_str
        real,    allocatable :: resarr(:)
        integer, allocatable :: pops(:)
        real    :: lplim_rec, fsc05, fsc0143
        integer :: istate
        allocate(part_str, source=int2str_pad(params_glob%part,params_glob%numlen))
        call build_glob%spproj_field%get_pops(pops, 'state')
        lplim_rec = huge(lplim_rec)
        resarr    = build_glob%img%get_res()
        do istate = 1, params_glob%nstates
            if( pops(istate) > 0)then
                call build_glob%eorecvols(istate)%new( build_glob%spproj)
                call build_glob%eorecvols(istate)%reset_all
                if( params_glob%l_frac_update )then
                    call build_glob%eorecvols(istate)%read_eos(trim(VOL_FBODY)//&
                        int2str_pad(istate,2)//'_part'//part_str)
                    call build_glob%eorecvols(istate)%expand_exp
                    call build_glob%eorecvols(istate)%apply_weight(1.0 - &
                        params_glob%update_frac)
                endif
                ! determining resolution for low-pass limited reconstruction
                if( any(build_glob%fsc(istate,:) > 0.143) )then
                    call get_resolution(build_glob%fsc(istate,:), resarr, fsc05, fsc0143)
                    lplim_rec = min(lplim_rec, fsc0143)
                endif
            endif
        end do
        deallocate(pops,resarr)
    end subroutine preprecvols

    !>  \brief  destructs all volumes for reconstruction
    subroutine killrecvols
        integer :: istate
        do istate = 1, params_glob%nstates
            call build_glob%eorecvols(istate)%kill
        end do
    end subroutine killrecvols

    !>  \brief  prepares a batch of image
    subroutine prepimgbatch( batchsz )
        integer,        intent(in)    :: batchsz
        integer :: currsz, ibatch
        logical :: doprep
        if( .not. allocated(build_glob%imgbatch) )then
            doprep = .true.
        else
            currsz = size(build_glob%imgbatch)
            if( batchsz > currsz )then
                do ibatch=1,currsz
                    call build_glob%imgbatch(ibatch)%kill
                end do
                deallocate(build_glob%imgbatch)
                doprep = .true.
            else
                doprep = .false.
            endif
        endif
        if( doprep )then
            allocate(build_glob%imgbatch(batchsz))
            do ibatch=1,batchsz
                call build_glob%imgbatch(ibatch)%new([params_glob%box,params_glob%box,1], &
                    params_glob%smpd, wthreads=.false.)
            end do
        endif
    end subroutine prepimgbatch

    !>  \brief  determines the reference volume shift and map shifts back to particles
    !>          reference volume shifting is performed in shift_and_mask_refvol
    subroutine calcrefvolshift_and_mapshifts2ptcls(cline, s, volfname, do_center, xyz )
        class(cmdline),   intent(inout) :: cline
        integer,          intent(in)    :: s
        character(len=*), intent(in)    :: volfname
        logical,          intent(out)   :: do_center
        real,             intent(out)   :: xyz(3)
        logical :: has_been_searched
        do_center = .true.
        ! ensure correct build_glob%vol dim
        call build_glob%vol%new([params_glob%box,params_glob%box,params_glob%box],params_glob%smpd)
        ! centering
        if( params_glob%center .eq. 'no' .or. params_glob%nstates > 1 .or. &
            .not. params_glob%l_doshift .or. params_glob%pgrp(:1) .ne. 'c' .or. &
            cline%defined('mskfile') .or. params_glob%l_frac_update )then
            do_center = .false.
            xyz       = 0.
            return
        endif
        call build_glob%vol%read(volfname)
        xyz = build_glob%vol%calc_shiftcen(params_glob%cenlp,params_glob%msk)
        if( params_glob%pgrp .ne. 'c1' ) xyz(1:2) = 0.     ! shifts only along z-axis for C2 and above
        if( arg(xyz) <= CENTHRESH )then
            do_center = .false.
            xyz       = 0.
            return
        endif
        ! map back to particle oritentations
        has_been_searched = .not.build_glob%spproj%is_virgin_field(params_glob%oritype)
        if( has_been_searched ) call build_glob%spproj_field%map3dshift22d(-xyz(:), state=s)
    end subroutine calcrefvolshift_and_mapshifts2ptcls

    subroutine read_and_filter_refvols( cline, fname_even, fname_odd )
        use simple_opt_filter, only: opt_filter_3D
        class(cmdline),   intent(in) :: cline
        character(len=*), intent(in) :: fname_even
        character(len=*), intent(in) :: fname_odd
        type(image)    :: mskvol
        ! ensure correct build_glob%vol dim
        call build_glob%vol%new([params_glob%box,params_glob%box,params_glob%box],params_glob%smpd)
        call build_glob%vol%read(fname_even)
        call build_glob%vol_odd%new([params_glob%box,params_glob%box,params_glob%box],params_glob%smpd)
        call build_glob%vol_odd%read(fname_odd)
        did_filter = .false.
        if( cline%defined('mskfile') .and. params_glob%l_nonuniform )then
            call mskvol%new([params_glob%box, params_glob%box, params_glob%box], params_glob%smpd)
            call mskvol%read(params_glob%mskfile)
            call mskvol%one_at_edge ! to expand before masking of reference
            call opt_filter_3D(build_glob%vol_odd, build_glob%vol, mskvol)
            did_filter = .true.
            ! envelope masking
            call mskvol%read(params_glob%mskfile) ! to bring back the edge
            call build_glob%vol%zero_env_background(mskvol)
            call build_glob%vol_odd%zero_env_background(mskvol)
            call build_glob%vol%mul(mskvol)
            call build_glob%vol_odd%mul(mskvol)
            call mskvol%kill
            call build_glob%vol%fft
            call build_glob%vol_odd%fft
        else
            ! expand for fast interpolation
            call build_glob%vol%fft
            call build_glob%vol_odd%fft
            if( params_glob%l_ran_noise_ph )then
                ! randomize Fourier phases below noise power in a global manner
                if( params_glob%clsfrcs.eq.'no' )&
                &call build_glob%vol%ran_phases_below_noise_power(build_glob%vol_odd)
            endif
        endif
    end subroutine read_and_filter_refvols

    !>  \brief  prepares one volume for references extraction
    subroutine preprefvol( pftcc, cline, s, do_center, xyz, iseven )
        use simple_polarft_corrcalc, only: polarft_corrcalc
        use simple_estimate_ssnr,    only: fsc2optlp_sub
        use simple_projector,        only: projector
        class(polarft_corrcalc), intent(inout) :: pftcc
        class(cmdline),          intent(inout) :: cline
        integer,                 intent(in)    :: s
        logical,                 intent(in)    :: do_center
        real,                    intent(in)    :: xyz(3)
        logical,                 intent(in)    :: iseven
        type(projector),  pointer     :: vol_ptr => null()
        real    :: filter(build_glob%img%get_filtsz()), frc(build_glob%img%get_filtsz())
        integer :: iref, iproj, filtsz
        if( iseven )then
            vol_ptr => build_glob%vol
        else
            vol_ptr => build_glob%vol_odd
        endif
        if( do_center )then
            call vol_ptr%fft()
            call vol_ptr%shift([xyz(1),xyz(2),xyz(3)])
        endif
        ! Volume filtering
        filtsz = build_glob%img%get_filtsz()
        if( params_glob%l_match_filt .and. .not. did_filter )then
            ! stores filters in pftcc
            if( params_glob%clsfrcs.eq.'yes')then
                if( file_exists(params_glob%frcs) )then
                    iproj = 0
                    do iref = 1,2*build_glob%clsfrcs%get_nprojs()
                        iproj = iproj+1
                        if( iproj > build_glob%clsfrcs%get_nprojs() ) iproj = 1
                        call build_glob%clsfrcs%frc_getter(iproj, params_glob%hpind_fsc, params_glob%l_phaseplate, frc)
                        call fsc2optlp_sub(filtsz, frc, filter)
                        call pftcc%set_ref_optlp(iref, filter(params_glob%kfromto(1):params_glob%kstop))
                    enddo
                endif
            else
                if( any(build_glob%fsc(s,:) > 0.143) )then
                    call fsc2optlp_sub(filtsz, build_glob%fsc(s,:), filter)
                else
                    filter = 1.
                endif
                do iref = (s-1)*params_glob%nspace+1, s*params_glob%nspace
                    call pftcc%set_ref_optlp(iref, filter(params_glob%kfromto(1):params_glob%kstop))
                enddo
            endif
        else
            if( params_glob%cc_objfun == OBJFUN_EUCLID )then
                ! no filtering
            else if( .not. did_filter )then
                call vol_ptr%fft()
                if( any(build_glob%fsc(s,:) > 0.143) )then
                    call fsc2optlp_sub(filtsz,build_glob%fsc(s,:),filter)
                    call vol_ptr%apply_filter(filter)
                endif
            endif
        endif
        ! back to real space
        call vol_ptr%ifft()
        ! masking
        if( cline%defined('mskfile') )then
            ! masking performed in readrefvols_filter_nonuniformly, above
        else
            ! circular masking
            if( params_glob%cc_objfun == OBJFUN_EUCLID )then
                call vol_ptr%mask(params_glob%msk, 'soft', backgr=0.0)
            else
                call vol_ptr%mask(params_glob%msk, 'soft')
            endif
        endif
        ! gridding prep
        if( params_glob%gridding.eq.'yes' )then
            call vol_ptr%div_w_instrfun(params_glob%interpfun, alpha=params_glob%alpha)
        endif
        ! FT volume
        call vol_ptr%fft()
        ! expand for fast interpolation & correct for norm when clipped
        call vol_ptr%expand_cmat(params_glob%alpha,norm4proj=.true.)
    end subroutine preprefvol

    subroutine norm_struct_facts( cline, which_iter )
        use simple_masker, only: masker
        class(cmdline), intent(inout) :: cline
        integer,        intent(in)    :: which_iter
        character(len=:), allocatable :: mskfile
        character(len=STDLEN) :: pprocvol, lpvol
        real, allocatable     :: optlp(:), res(:)
        type(masker)          :: envmsk
        integer               :: s, find4eoavg, ldim(3)
        real                  :: res05s(params_glob%nstates), res0143s(params_glob%nstates), lplim, bfac
        logical               :: l_automsk
        ! set automask flag
        l_automsk = .false.
        if( cline%defined('automsk') )then
            l_automsk = cline%get_carg('automsk') .eq. 'yes'
        endif
        ! init
        ldim = [params_glob%box,params_glob%box,params_glob%box]
        call build_glob%vol%new(ldim,params_glob%smpd)
        call build_glob%vol2%new(ldim,params_glob%smpd)
        res0143s = 0.
        res05s   = 0.
        ! cycle through states
        do s=1,params_glob%nstates
            if( build_glob%spproj_field%get_pop(s, 'state') == 0 )then
                ! empty state
                build_glob%fsc(s,:) = 0.
                cycle
            endif
            call build_glob%eorecvols(s)%compress_exp
            if( params_glob%l_distr_exec )then
                call build_glob%eorecvols(s)%write_eos('recvol_state'//int2str_pad(s,2)//'_part'//&
                    int2str_pad(params_glob%part,params_glob%numlen))
            else
                if( trim(params_glob%refine) .eq. 'snhc' )then
                    params_glob%vols(s) = trim(SNHCVOL)//trim(int2str_pad(s,2))//params_glob%ext
                else
                    params_glob%vols(s) = 'recvol_state'//int2str_pad(s,2)//'_iter'//int2str_pad(which_iter,3)//params_glob%ext
                endif
                if( cline%defined('mskfile') .and. params_glob%l_envfsc )then
                    call build_glob%eorecvols(s)%set_automsk(.true.)
                endif
                params_glob%vols_even(s) = add2fbody(params_glob%vols(s), params_glob%ext, '_even')
                params_glob%vols_odd(s)  = add2fbody(params_glob%vols(s), params_glob%ext, '_odd')
                call build_glob%eorecvols(s)%sum_eos
                call build_glob%eorecvols(s)%sampl_dens_correct_eos(s, params_glob%vols_even(s), &
                    &params_glob%vols_odd(s), find4eoavg)
                call build_glob%eorecvols(s)%get_res(res05s(s), res0143s(s))
                call build_glob%eorecvols(s)%sampl_dens_correct_sum(build_glob%vol)
                call build_glob%vol%write(params_glob%vols(s), del_if_exists=.true.)
                call simple_copy_file(trim(params_glob%vols(s)),trim(VOL_FBODY)//int2str_pad(s,2)//params_glob%ext)
                ! need to put the sum back at lowres for the eo pairs
                call build_glob%vol%fft()
                call build_glob%vol2%zero_and_unflag_ft
                call build_glob%vol2%read(params_glob%vols_even(s))
                call build_glob%vol2%fft()
                call build_glob%vol2%insert_lowres(build_glob%vol, find4eoavg)
                call build_glob%vol2%ifft()
                call build_glob%vol2%write(params_glob%vols_even(s), del_if_exists=.true.)
                call build_glob%vol2%zero_and_unflag_ft
                call build_glob%vol2%read(params_glob%vols_odd(s))
                call build_glob%vol2%fft()
                call build_glob%vol2%insert_lowres(build_glob%vol, find4eoavg)
                call build_glob%vol2%ifft()
                call build_glob%vol2%write(params_glob%vols_odd(s), del_if_exists=.true.)
                ! post-process volume
                pprocvol = add2fbody(trim(params_glob%vols(s)), params_glob%ext, PPROC_SUFFIX)
                lpvol    = add2fbody(trim(params_glob%vols(s)), params_glob%ext, LP_SUFFIX)
                build_glob%fsc(s,:) = file2rarr('fsc_state'//int2str_pad(s,2)//'.bin')
                ! low-pass limit
                if( params_glob%l_lpset )then
                    lplim = params_glob%lp
                else
                    lplim = res0143s(s)
                endif
                ! B-factor estimation
                if( cline%defined('bfac') )then
                    bfac = params_glob%bfac
                else
                    bfac = build_glob%vol%guinier_bfac(HPLIM_GUINIER, lplim)
                    write(logfhandle,'(A,1X,F8.2)') '>>> B-FACTOR DETERMINED TO:', bfac
                endif
                ! B-factor application
                call build_glob%vol2%copy(build_glob%vol)
                call build_glob%vol%apply_bfac(bfac)
                ! low-pass filter
                if( params_glob%l_lpset )then
                    call build_glob%vol%bp(0., lplim)
                    call build_glob%vol2%bp(0., lplim)
                else
                    res   = build_glob%vol%get_res()
                    optlp = fsc2optlp(build_glob%fsc(s,:))
                    where( res < TINY ) optlp = 0.
                    lplim = res0143s(s)
                    ! optimal low-pass filter from FSC
                    call build_glob%vol%apply_filter(optlp)
                    call build_glob%vol2%apply_filter(optlp)
                    ! final low-pass filtering for smoothness
                    call build_glob%vol%bp(0., res0143s(s))
                    call build_glob%vol2%bp(0., res0143s(s))
                endif
                call build_glob%vol%ifft()
                call build_glob%vol2%ifft()
                ! write low-pass filtered without B-factor or mask
                call build_glob%vol2%write(lpvol)
                ! masking
                if( l_automsk .or. cline%defined('mskfile') )then
                    if( l_automsk )then
                        call cline%delete('mskfile')
                        ! use the non-sharpened volume to make a mask
                        call envmsk%automask3D_otsu(build_glob%vol2, do_apply=.false.)
                        mskfile = 'automask'//params_glob%ext
                        call envmsk%write(mskfile)
                        call cline%set('mskfile', mskfile)
                        params_glob%mskfile = mskfile
                    endif
                    if( cline%defined('mskfile') )then
                        mskfile = cline%get_carg('mskfile')
                        if( .not. file_exists(mskfile) ) THROW_HARD('File '//mskfile//' does not exist')
                        params_glob%mskfile = mskfile
                        call envmsk%new(ldim, params_glob%smpd)
                        call envmsk%read(mskfile)
                    endif
                    call build_glob%vol%zero_background
                    if( cline%defined('lp_backgr') )then
                        call build_glob%vol%lp_background(envmsk,params_glob%lp_backgr)
                    else
                        call build_glob%vol%mul(envmsk)
                    endif
                    call envmsk%kill
                else
                    call build_glob%vol%mask(params_glob%msk, 'soft')
                endif
                ! write
                call build_glob%vol%write(pprocvol)
            endif
        end do
        if( .not. params_glob%l_distr_exec )then
            ! set the resolution limit according to the worst resolved model
            params_glob%lp = min(params_glob%lp,max(params_glob%lpstop,maxval(res0143s)))
        endif
        call build_glob%vol2%kill
    end subroutine norm_struct_facts

end module simple_strategy2D3D_common
