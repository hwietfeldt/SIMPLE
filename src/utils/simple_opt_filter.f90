! optimization(search)-based filter (uniform/nonuniform)
module simple_opt_filter
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_defs
use simple_fftw3
use simple_image,      only: image, image_ptr
use simple_parameters, only: params_glob
implicit none
#include "simple_local_flags.inc"

public :: opt_vol, opt_2D_filter_sub_test, opt_2D_filter_sub, opt_filter_2D, opt_filter_3D_test, opt_filter_3D, butterworth_filter
private

type opt_vol
    real :: opt_val
    real :: opt_diff
    real :: opt_freq
end type opt_vol

type fft_vars_type
    type(c_ptr)                            :: plan_fwd, plan_bwd
    real(   kind=c_float),         pointer ::  in(:,:,:)
    complex(kind=c_float_complex), pointer :: out(:,:,:)
end type fft_vars_type

contains
    subroutine batch_fft_2D( even, odd, fft_vars )
        class(image),        intent(inout) :: even, odd
        type(fft_vars_type), intent(in)    :: fft_vars
        integer            :: ldim(3), k, l
        type(image_ptr)    :: peven, podd
        ldim = even%get_ldim()
        call even%set_ft(.false.)
        call  odd%set_ft(.false.)
        call even%get_mat_ptrs(peven)
        call  odd%get_mat_ptrs(podd)
        !$omp parallel do collapse(2) default(shared) private(k,l) schedule(static) proc_bind(close)
        do l = 1, ldim(2)
            do k = 1, ldim(1)
                fft_vars%in(k,l,1) = peven%rmat(k,l,1)
                fft_vars%in(k,l,2) =  podd%rmat(k,l,1)
            enddo
        enddo
        !$omp end parallel do
        call fftwf_execute_dft_r2c(fft_vars%plan_fwd, fft_vars%in, fft_vars%out)
        call even%set_ft(.true.)
        call  odd%set_ft(.true.)
        !$omp parallel do collapse(2) default(shared) private(k,l) schedule(static) proc_bind(close)
        do l = 1, ldim(2)
            do k = 1, ldim(1)/2+1
                if( mod(k+l,2) == 1 )then
                    peven%cmat(k,l,1) = -fft_vars%out(k,l,1)/product(ldim(1:2))
                    podd %cmat(k,l,1) = -fft_vars%out(k,l,2)/product(ldim(1:2))
                else
                    peven%cmat(k,l,1) =  fft_vars%out(k,l,1)/product(ldim(1:2))
                    podd %cmat(k,l,1) =  fft_vars%out(k,l,2)/product(ldim(1:2))
                endif
            enddo
        enddo
        !$omp end parallel do
    end subroutine batch_fft_2D

    subroutine batch_ifft_2D( even, odd, fft_vars )
        class(image),        intent(inout) :: even, odd
        type(fft_vars_type), intent(in)    :: fft_vars
        integer            :: ldim(3), k, l
        type(image_ptr)    :: peven, podd
        ldim = even%get_ldim()
        call even%set_ft(.true.)
        call  odd%set_ft(.true.)
        call even%get_mat_ptrs(peven)
        call  odd%get_mat_ptrs(podd)
        !$omp parallel do collapse(2) default(shared) private(k,l) schedule(static) proc_bind(close)
        do l = 1, ldim(2)
            do k = 1, ldim(1)/2+1
                if( mod(k+l,2) == 1 )then
                    fft_vars%out(k,l,1) = -peven%cmat(k,l,1)
                    fft_vars%out(k,l,2) = - podd%cmat(k,l,1)
                else
                    fft_vars%out(k,l,1) = peven%cmat(k,l,1)
                    fft_vars%out(k,l,2) =  podd%cmat(k,l,1)
                endif
            enddo
        enddo
        !$omp end parallel do
        call fftwf_execute_dft_c2r(fft_vars%plan_bwd, fft_vars%out, fft_vars%in)
        call even%set_ft(.false.)
        call  odd%set_ft(.false.)
        !$omp parallel do collapse(2) default(shared) private(k,l) schedule(static) proc_bind(close)
        do l = 1, ldim(2)
            do k = 1, ldim(1)
                peven%rmat(k,l,1) = fft_vars%in(k,l,1)
                podd %rmat(k,l,1) = fft_vars%in(k,l,2)
            enddo
        enddo
        !$omp end parallel do
    end subroutine batch_ifft_2D

    subroutine batch_fft_3D( even, odd, in, out, plan_fwd)
        class(image),                           intent(inout) :: even, odd
        real(   kind=c_float),         pointer, intent(inout) ::  in(:,:,:,:)
        complex(kind=c_float_complex), pointer, intent(inout) :: out(:,:,:,:)
        type(c_ptr),                            intent(in)    :: plan_fwd
        integer            :: ldim(3), k, l, m
        type(image_ptr)    :: peven, podd
        ldim = even%get_ldim()
        call even%set_ft(.false.)
        call  odd%set_ft(.false.)
        call even%get_mat_ptrs(peven)
        call  odd%get_mat_ptrs(podd)
        !$omp parallel do collapse(3) default(shared) private(k,l,m) schedule(static) proc_bind(close)
        do m = 1, ldim(3)
            do l = 1, ldim(2)
                do k = 1, ldim(1)
                    in(k,l,m,1) = peven%rmat(k,l,m)
                    in(k,l,m,2) =  podd%rmat(k,l,m)
                enddo
            enddo
        enddo
        !$omp end parallel do
        call fftwf_execute_dft_r2c(plan_fwd, in, out)
        call even%set_ft(.true.)
        call  odd%set_ft(.true.)
        !$omp parallel do collapse(3) default(shared) private(k,l,m) schedule(static) proc_bind(close)
        do m = 1, ldim(3)
            do l = 1, ldim(2)
                do k = 1, ldim(1)/2+1
                    if( mod(k+l+m,2) == 0 )then
                        peven%cmat(k,l,m) = -out(k,l,m,1)/product(ldim)
                        podd %cmat(k,l,m) = -out(k,l,m,2)/product(ldim)
                    else
                        peven%cmat(k,l,m) =  out(k,l,m,1)/product(ldim)
                        podd %cmat(k,l,m) =  out(k,l,m,2)/product(ldim)
                    endif
                enddo
            enddo
        enddo
        !$omp end parallel do
    end subroutine batch_fft_3D

    subroutine batch_ifft_3D( even, odd, in, out, plan_bwd)
        class(image),                           intent(inout) :: even, odd
        real(   kind=c_float),         pointer, intent(inout) ::  in(:,:,:,:)
        complex(kind=c_float_complex), pointer, intent(inout) :: out(:,:,:,:)
        type(c_ptr),                            intent(in)    :: plan_bwd
        integer            :: ldim(3), k, l, m
        type(image_ptr)    :: peven, podd
        ldim = even%get_ldim()
        call even%set_ft(.true.)
        call  odd%set_ft(.true.)
        call even%get_mat_ptrs(peven)
        call  odd%get_mat_ptrs(podd)
        !$omp parallel do collapse(3) default(shared) private(k,l,m) schedule(static) proc_bind(close)
        do m = 1, ldim(3)
            do l = 1, ldim(2)
                do k = 1, ldim(3)/2+1
                    if( mod(k+l+m,2) == 0 )then
                        out(k,l,m,1) = -peven%cmat(k,l,m)
                        out(k,l,m,2) =  -podd%cmat(k,l,m)
                    else
                        out(k,l,m,1) = peven%cmat(k,l,m)
                        out(k,l,m,2) =  podd%cmat(k,l,m)
                    endif
                enddo
            enddo
        enddo
        !$omp end parallel do
        call fftwf_execute_dft_c2r(plan_bwd, out, in)
        call even%set_ft(.false.)
        call  odd%set_ft(.false.)
        !$omp parallel do collapse(3) default(shared) private(k,l,m) schedule(static) proc_bind(close)
        do m = 1, ldim(3)
            do l = 1, ldim(2)
                do k = 1, ldim(1)
                    peven%rmat(k,l,m) = in(k,l,m,1)
                    podd%rmat(k,l,m)  = in(k,l,m,2)
                enddo
            enddo
        enddo
        !$omp end parallel do
    end subroutine batch_ifft_3D

    subroutine opt_2D_filter_sub_test( even, odd )
        use simple_tvfilter,   only: tvfilter
        use simple_class_frcs, only: class_frcs
        class(image),   intent(inout) :: even(:), odd(:)
        character(len=:), allocatable :: filter, frcs_fname
        type(tvfilter)                :: tvfilt
        type(class_frcs)              :: clsfrcs 
        type(image),      allocatable :: weights_img(:), ref_diff_odd_img(:), ref_diff_even_img(:),&
                                        &odd_copy_rmat(:),  odd_copy_cmat(:),  odd_copy_shellnorm(:),&
                                        &even_copy_rmat(:), even_copy_cmat(:), even_copy_shellnorm(:)
        real,             allocatable :: cur_fil(:,:), weights_2D(:,:,:), frc(:)
        integer,          allocatable :: lplims_hres(:)
        type(opt_vol),    allocatable :: opt_odd(:,:,:,:), opt_even(:,:,:,:)
        real                          :: smpd, lpstart, lp
        integer                       :: iptcl, box, filtsz, ldim(3), ldim_pd(3), smooth_ext, nptcls, hpind_fsc, find
        logical                       :: lpstart_fallback, l_nonuniform, l_phaseplate
        integer(timer_int_kind)       :: t_tot
        type(c_ptr)                   :: ptr
        integer                       :: c_shape(3)
        integer,             parameter   :: N_IMGS = 2
        type(fft_vars_type), allocatable :: fft_vars(:)
        ! init
        ldim         = even(1)%get_ldim()
        filtsz       = even(1)%get_filtsz()
        ldim(3)      = 1 ! because we operate on stacks
        smooth_ext   = params_glob%smooth_ext
        ldim_pd      = ldim + 2 * smooth_ext
        ldim_pd(3)   = 1 ! because we operate on stacks
        box          = ldim_pd(1)
        filter       = trim(params_glob%filter)
        l_nonuniform = params_glob%l_nonuniform
        frcs_fname   = trim(params_glob%frcs)
        smpd         = params_glob%smpd
        nptcls       = size(even)
        lpstart      = params_glob%lpstart
        hpind_fsc    = params_glob%hpind_fsc
        l_phaseplate = params_glob%l_phaseplate

        ! print *, 'ldim         ', ldim(1),    ldim(2),    ldim(3)
        ! print *, 'ldim_pd      ', ldim_pd(1), ldim_pd(2), ldim_pd(3)
        ! print *, 'filtsz       ', filtsz
        ! print *, 'box          ', box
        ! print *, 'filter       ', filter
        ! print *, 'l_nonuniform ', l_nonuniform
        ! print *, 'smooth_ext   ', smooth_ext
        ! print *, 'frcs_fname   ', frcs_fname
        ! print *, 'smpd         ', smpd
        ! print *, 'nptcls       ', nptcls
        ! print *, 'lpstart      ', lpstart
        ! print *, 'hpind_fsc    ', hpind_fsc
        ! print *, 'l_phaseplate ', l_phaseplate

        ! retrieve FRCs
        call clsfrcs%new(nptcls, box, smpd, 1)
        lpstart_fallback = .false.
        if( file_exists(frcs_fname) )then
            call clsfrcs%read(frcs_fname)
        else
            THROW_WARN('Class average FRCs file '//frcs_fname//' does not exist, falling back on lpstart: '//real2str(lpstart))
            lpstart_fallback = .true.
        endif
        filtsz = clsfrcs%get_filtsz()
        ! allocate
        allocate(odd_copy_rmat(nptcls),  odd_copy_cmat(nptcls),  odd_copy_shellnorm(nptcls),&
                &even_copy_rmat(nptcls), even_copy_cmat(nptcls), even_copy_shellnorm(nptcls),&
                &weights_img(nptcls), ref_diff_odd_img(nptcls), ref_diff_even_img(nptcls))
        allocate(cur_fil(box,nptcls),weights_2D(smooth_ext*2+1,&
                &smooth_ext*2+1,nptcls), frc(filtsz), source=0.)
        allocate(opt_odd(box,box,1,nptcls), opt_even(box,box,1,nptcls), lplims_hres(nptcls))
        ! calculate high-res low-pass limits
        if( lpstart_fallback )then
            lplims_hres = calc_fourier_index(lpstart, box, smpd)
        else
            do iptcl = 1, nptcls
                call clsfrcs%frc_getter(iptcl, hpind_fsc, l_phaseplate, frc)
                ! the below required to retrieve the right Fouirer index limit when we are padding
                find = get_lplim_at_corr(frc, LPLIM_CRIT2D)
                lp   = calc_lowpass_lim(find, box, smpd)               ! box is the padded box size
                lplims_hres(iptcl) = calc_fourier_index(lp, box, smpd) ! this is the Fourier index limit for the padded images
            end do
        endif
        do iptcl = 1, nptcls
            call even(iptcl)%pad_mirr(ldim_pd)
            call odd( iptcl)%pad_mirr(ldim_pd)
        enddo
        ! construct
        allocate(fft_vars(nptcls))
        call fftwf_plan_with_nthreads(nthr_glob)
        c_shape = [ldim_pd(1), ldim_pd(2), N_IMGS]
        do iptcl = 1, nptcls
            ptr = fftwf_alloc_complex(int(product(c_shape),c_size_t))
            call c_f_pointer(ptr,fft_vars(iptcl)%out,c_shape)
            call c_f_pointer(ptr,fft_vars(iptcl)%in ,c_shape)
            !$omp critical
            fft_vars(iptcl)%plan_fwd = fftwf_plan_many_dft_r2c(2, [ldim_pd(2), ldim_pd(1)], N_IMGS,&
                                                &fft_vars(iptcl)%in ,[ldim_pd(2), ldim_pd(1)], 1, product([ldim_pd(2), ldim_pd(1)]),&
                                                &fft_vars(iptcl)%out,[ldim_pd(2), ldim_pd(1)], 1, product([ldim_pd(2), ldim_pd(1)]),FFTW_ESTIMATE)
            fft_vars(iptcl)%plan_bwd = fftwf_plan_many_dft_c2r(2, [ldim_pd(2), ldim_pd(1)], N_IMGS,&
                                                &fft_vars(iptcl)%out,[ldim_pd(2), ldim_pd(1)], 1, product([ldim_pd(2), ldim_pd(1)]),&
                                                &fft_vars(iptcl)%in ,[ldim_pd(2), ldim_pd(1)], 1, product([ldim_pd(2), ldim_pd(1)]),FFTW_ESTIMATE)
            !$omp end critical
        enddo
        do iptcl = 1, nptcls
            call weights_img(iptcl)%new(ldim_pd, smpd, .false.)
            call ref_diff_odd_img( iptcl)%new(ldim_pd, smpd, .false.)
            call ref_diff_even_img(iptcl)%new(ldim_pd, smpd, .false.)
            call odd_copy_rmat(iptcl)%copy(odd(iptcl))
            call odd_copy_cmat(iptcl)%copy(odd(iptcl))
            call odd_copy_shellnorm(iptcl)%copy(odd(iptcl))
            call odd_copy_shellnorm(iptcl)%shellnorm(return_ft=.true.)
            call even_copy_rmat(iptcl)%copy(even(iptcl))
            call even_copy_cmat(iptcl)%copy(even(iptcl))
            call batch_fft_2D(even_copy_cmat(iptcl), odd_copy_cmat(iptcl), fft_vars(iptcl))
            call even_copy_shellnorm(iptcl)%copy(even(iptcl))
            call even_copy_shellnorm(iptcl)%shellnorm(return_ft=.true.)
        enddo
        call tvfilt%new(odd(1))
        ! filter
        t_tot = tic()
        !$omp parallel do default(shared) private(iptcl) schedule(static) proc_bind(close)
        do iptcl = 1, nptcls
            call opt_filter_2D_test(odd(iptcl), even(iptcl),&
                            & odd_copy_rmat(iptcl),  odd_copy_cmat(iptcl),  odd_copy_shellnorm(iptcl),&
                            &even_copy_rmat(iptcl), even_copy_cmat(iptcl), even_copy_shellnorm(iptcl),&
                            &tvfilt, cur_fil(:,iptcl), weights_2D(:,:,iptcl), lplims_hres(iptcl),&
                            &opt_odd(:,:,:,iptcl), opt_even(:,:,:,iptcl),&
                            &weights_img(iptcl), ref_diff_odd_img(iptcl), ref_diff_even_img(iptcl),&
                            &fft_vars(iptcl))
        enddo
        !$omp end parallel do
        print *, 'timing = ', toc()
        ! destruct
        do iptcl = 1, nptcls
            call odd_copy_rmat( iptcl)%kill
            call even_copy_rmat(iptcl)%kill
            call odd_copy_cmat( iptcl)%kill
            call even_copy_cmat(iptcl)%kill
            call odd_copy_shellnorm( iptcl)%kill
            call even_copy_shellnorm(iptcl)%kill
            call weights_img(iptcl)%kill
            call ref_diff_odd_img( iptcl)%kill
            call ref_diff_even_img(iptcl)%kill
            call even(iptcl)%clip_inplace(ldim)
            call odd(iptcl)%clip_inplace(ldim)
            call fftwf_destroy_plan(fft_vars(iptcl)%plan_fwd)
            call fftwf_destroy_plan(fft_vars(iptcl)%plan_bwd)
            call fftwf_plan_with_nthreads(1)
        enddo
        call tvfilt%kill()
    end subroutine opt_2D_filter_sub_test

    subroutine apply_opt_filter_test(img, cur_ind, find_start, find_stop, cur_fil, use_cache, tvfilt_in)
        use simple_tvfilter, only: tvfilter
        class(image), intent(inout) :: img
        integer,      intent(in)    :: cur_ind
        integer,      intent(in)    :: find_start
        integer,      intent(in)    :: find_stop
        real,         intent(inout) :: cur_fil(:)
        logical,      intent(in)    :: use_cache
        type(tvfilter), optional, intent(inout) :: tvfilt_in
        integer, parameter :: BW_ORDER = 8
        real,    parameter :: LAMBDA_MIN = .5 , LAMBDA_MAX = 5.    ! for TV filter
        real               :: param
        type(tvfilter)     :: tvfilt_loc
        select case(params_glob%filt_enum)
            case(FILT_LP)
                call img%lp(cur_ind)
            case(FILT_TV)
                param = LAMBDA_MIN + (cur_ind - find_start)*(LAMBDA_MAX - LAMBDA_MIN)/(find_stop - find_start)
                if( .not. present(tvfilt_in) )then
                    call tvfilt_loc%new
                    if( img%is_2d() )then
                        call tvfilt_loc%apply_filter(img, param)
                    else
                        call tvfilt_loc%apply_filter_3d(img, param)
                    endif
                    call tvfilt_loc%kill
                else
                    if( img%is_2d() )then
                        call tvfilt_in%apply_filter(img, param)
                    else
                        call tvfilt_in%apply_filter_3d(img, param)
                    endif
                endif
            case(FILT_BW8)
                if( .not. use_cache ) call butterworth_filter(cur_fil, BW_ORDER, real(cur_ind))
                call img%apply_filter(cur_fil)
            case DEFAULT
                THROW_HARD('unsupported filter type')
        end select
    end subroutine apply_opt_filter_test

    ! 2D optimization(search)-based uniform/nonuniform filter, serial (strictly non-paralellized) version
    subroutine opt_filter_2D_test(odd, even,&
                                 &odd_copy_rmat,  odd_copy_cmat,  odd_copy_shellnorm,&
                                 &even_copy_rmat, even_copy_cmat, even_copy_shellnorm,&
                                 &tvfilt_in, cur_fil, weights_2D, kstop,&
                                 &opt_odd, opt_even, weights_img, ref_diff_odd_img, ref_diff_even_img,&
                                 &fft_vars)
        use simple_tvfilter, only: tvfilter
        class(image),   intent(inout) :: odd
        class(image),   intent(inout) :: even
        class(image),   intent(in)    :: odd_copy_rmat,  odd_copy_cmat,  odd_copy_shellnorm,&
                                        &even_copy_rmat, even_copy_cmat, even_copy_shellnorm
        type(tvfilter), intent(inout) :: tvfilt_in
        real,           intent(inout) :: cur_fil(:), weights_2D(:,:)
        integer,        intent(in)    :: kstop
        type(opt_vol),  intent(inout) :: opt_odd(:,:,:), opt_even(:,:,:)
        class(image),   intent(inout) :: weights_img, ref_diff_odd_img, ref_diff_even_img
        type(fft_vars_type) , intent(in) :: fft_vars
        integer           :: k,l,m,n, box, dim3, ldim(3), find_start, find_stop, iter_no, ext
        integer           :: best_ind, cur_ind, lb(3), ub(3)
        real              :: min_sum_odd, min_sum_even, rad, find_stepsz, val
        real, pointer     :: rmat_odd(:,:,:), rmat_even(:,:,:)
        type(image_ptr)   :: podd, peven, pweights
        ! init
        ldim              = odd%get_ldim()
        box               = ldim(1)
        dim3              = ldim(3)
        if( dim3 > 1 ) THROW_HARD('This opt_filter_2D is strictly for 2D case only!')
        ext               = params_glob%smooth_ext
        find_stop         = kstop
        find_start        = calc_fourier_index(params_glob%lp_lowres,  box, params_glob%smpd)
        find_stepsz       = real(find_stop - find_start)/(params_glob%nsearch - 1)
        lb                = (/ ext+1  , ext+1  , 1/)
        ub                = (/ box-ext, box-ext, dim3 /)
        ! searching for the best fourier index from here and generating the optimized filter
        min_sum_odd       = huge(min_sum_odd)
        min_sum_even      = huge(min_sum_even)
        best_ind          = find_start
        opt_odd%opt_val   = 0.
        opt_odd%opt_diff  = 0.
        opt_odd%opt_freq  = 0.
        opt_even%opt_val  = 0.
        opt_even%opt_diff = 0.
        opt_even%opt_freq = 0.
        opt_odd( lb(1):ub(1),lb(2):ub(2),lb(3):ub(3))%opt_diff = huge(min_sum_odd)
        opt_even(lb(1):ub(1),lb(2):ub(2),lb(3):ub(3))%opt_diff = huge(min_sum_odd)
        call       weights_img%get_mat_ptrs(pweights)
        call  ref_diff_odd_img%get_mat_ptrs(podd)
        call ref_diff_even_img%get_mat_ptrs(peven)
        call weights_img%zero_and_unflag_ft()
        do m = -ext, ext
            do n = -ext, ext
                rad = hyp(real(m), real(n))
                val = -rad/(ext + 1) + 1.
                if( val > 0 ) call weights_img%set_rmat_at(box/2+m+1, box/2+n+1, 1, val)
            enddo
        enddo
        call weights_img%fft()
        do iter_no = 1, params_glob%nsearch
            cur_ind = nint(find_start + (iter_no - 1)*find_stepsz)
            if( L_VERBOSE_GLOB ) write(*,*) '('//int2str(iter_no)//'/'//int2str(params_glob%nsearch)//') current Fourier index = ', cur_ind
            ! filtering odd/even
            call  odd%copy_fast( odd_copy_cmat)
            call even%copy_fast(even_copy_cmat)
            call apply_opt_filter_test( odd, cur_ind, find_start, find_stop, cur_fil, .false., tvfilt_in)
            call apply_opt_filter_test(even, cur_ind, find_start, find_stop, cur_fil, .false., tvfilt_in)
            call batch_ifft_2D(even, odd, fft_vars)
            call  odd%sqeuclid_matrix(even_copy_rmat, ref_diff_odd_img)
            call even%sqeuclid_matrix( odd_copy_rmat, ref_diff_even_img)
            if( params_glob%l_match_filt )then
                call  odd%copy_fast( odd_copy_shellnorm)
                call even%copy_fast(even_copy_shellnorm)
                call apply_opt_filter_test( odd, cur_ind, find_start, find_stop, cur_fil, .false., tvfilt_in)
                call apply_opt_filter_test(even, cur_ind, find_start, find_stop, cur_fil, .false., tvfilt_in)
                call batch_ifft_2D(even, odd, fft_vars)
            endif
            call  odd%get_rmat_ptr(rmat_odd)
            call even%get_rmat_ptr(rmat_even)
            ! do the non-uniform, i.e. optimizing at each voxel
            if( params_glob%l_nonuniform )then                    
                call batch_fft_2D(ref_diff_even_img, ref_diff_odd_img, fft_vars)
                podd%cmat  =  podd%cmat * pweights%cmat
                peven%cmat = peven%cmat * pweights%cmat
                call batch_ifft_2D(ref_diff_even_img, ref_diff_odd_img, fft_vars)
                do l = lb(2),ub(2)
                    do k = lb(1),ub(1)
                        if (podd%rmat(k,l,1) < opt_odd(k,l,1)%opt_diff) then
                            opt_odd(k,l,1)%opt_val  = rmat_odd(k,l,1)
                            opt_odd(k,l,1)%opt_diff = podd%rmat(k,l,1)
                            opt_odd(k,l,1)%opt_freq = cur_ind
                        endif
                        if (peven%rmat(k,l,1) < opt_even(k,l,1)%opt_diff) then
                            opt_even(k,l,1)%opt_val  = rmat_even(k,l,1)
                            opt_even(k,l,1)%opt_diff = peven%rmat(k,l,1)
                            opt_even(k,l,1)%opt_freq = cur_ind
                        endif
                    enddo
                enddo
            else
                ! keep the theta which gives the lowest cost (over all voxels)
                if (sum(podd%rmat) < min_sum_odd) then
                    opt_odd(:,:,:)%opt_val  = rmat_odd(1:box, 1:box, 1:dim3)
                    opt_odd(:,:,:)%opt_freq = cur_ind
                    min_sum_odd  = sum(podd%rmat)
                    best_ind     = cur_ind
                endif
                if (sum(peven%rmat) < min_sum_even) then
                    opt_even(:,:,:)%opt_val  = rmat_even(1:box, 1:box, 1:dim3)
                    opt_even(:,:,:)%opt_freq = cur_ind
                    min_sum_even  = sum(peven%rmat)
                endif
            endif
            if( L_VERBOSE_GLOB ) write(*,*) 'current cost (odd) = ', sum(podd%rmat)
        enddo
        if( L_VERBOSE_GLOB )then
            if( .not. params_glob%l_nonuniform ) write(*,*) 'minimized cost at resolution = ', box*params_glob%smpd/best_ind
        endif
        do k = 1,ldim(1)
            do l = 1,ldim(2)
                call  odd%set_rmat_at(k,l,1,opt_odd( k,l,1)%opt_val)
                call even%set_rmat_at(k,l,1,opt_even(k,l,1)%opt_val)
            enddo
        enddo
    end subroutine opt_filter_2D_test

    ! 3D optimization(search)-based uniform/nonuniform filter, paralellized version
    subroutine opt_filter_3D_test(odd, even, mskimg)
        class(image),           intent(inout) :: odd
        class(image),           intent(inout) :: even
        class(image), optional, intent(inout) :: mskimg
        type(image)                ::  odd_copy_rmat,  odd_copy_cmat,  odd_copy_shellnorm, freq_img,&
                                        &even_copy_rmat, even_copy_cmat, even_copy_shellnorm, &
                                        &weights_img, ref_diff_odd_img, ref_diff_even_img
        integer                    :: k,l,m, box, ldim(3), find_start, find_stop, iter_no, fnr
        integer                    :: best_ind, cur_ind, lb(3), ub(3), ext
        real                       :: min_sum_odd, min_sum_even, rad, find_stepsz, val
        character(len=90)          :: file_tag
        integer,       parameter   :: CHUNKSZ = 20, N_IMGS = 2
        type(image_ptr)            :: podd, peven, pweights
        type(c_ptr)                :: plan_fwd, plan_bwd
        real,          pointer     :: rmat_odd(:,:,:), rmat_even(:,:,:)
        real,          allocatable :: cur_fil(:), weights_3D(:,:,:)
        type(opt_vol), allocatable :: opt_odd(:,:,:), opt_even(:,:,:)
        character(len=LONGSTRLEN)  :: benchfname
        integer(timer_int_kind)    ::  t_tot,  t_filter_all,  t_search_opt,  t_chop_copy,  t_chop_filter,  t_chop_sqeu
        real(timer_int_kind)       :: rt_tot, rt_filter_all, rt_search_opt, rt_chop_copy, rt_chop_filter, rt_chop_sqeu
        real(kind=c_float), pointer                 ::  in(:,:,:,:)
        complex(kind=c_float_complex), pointer      :: out(:,:,:,:)
        ldim        = odd%get_ldim()
        box         = ldim(1)
        ext         = params_glob%smooth_ext
        find_stop   = calc_fourier_index(2. * params_glob%smpd,      box, params_glob%smpd)
        find_start  = calc_fourier_index(     params_glob%lp_lowres, box, params_glob%smpd)
        find_stepsz = real(find_stop - find_start)/(params_glob%nsearch - 1)
        call          freq_img%new(ldim, params_glob%smpd)
        call       weights_img%new(ldim, params_glob%smpd)
        call  ref_diff_odd_img%new(ldim, params_glob%smpd)
        call ref_diff_even_img%new(ldim, params_glob%smpd)
        call       weights_img%get_mat_ptrs(pweights)
        call  ref_diff_odd_img%get_mat_ptrs(podd)
        call ref_diff_even_img%get_mat_ptrs(peven)
        call odd_copy_rmat%copy(odd)
        call odd_copy_cmat%copy(odd)
        call odd_copy_cmat%fft
        call odd_copy_shellnorm%copy(odd)
        call odd_copy_shellnorm%shellnorm(return_ft=.true.)
        call even_copy_rmat%copy(even)
        call even_copy_cmat%copy(even)
        call even_copy_cmat%fft
        call even_copy_shellnorm%copy(even)
        call even_copy_shellnorm%shellnorm(return_ft=.true.)
        allocate(cur_fil(box), weights_3D(ext*2+1,ext*2+1, ext*2+1), source=0.)
        allocate(opt_odd(box,box,box), opt_even(box,box,box))
        allocate(in(ldim(1), ldim(2), ldim(3), 2))
        allocate(out(ldim(1), ldim(2), ldim(3), 2))
        !$omp critical
        call fftwf_plan_with_nthreads(nthr_glob)
        plan_fwd = fftwf_plan_many_dft_r2c(3, ldim, N_IMGS, in , ldim, 1, product(ldim), out, ldim, 1, product(ldim),FFTW_ESTIMATE)
        plan_bwd = fftwf_plan_many_dft_c2r(3, ldim, N_IMGS, out, ldim, 1, product(ldim),  in, ldim, 1, product(ldim),FFTW_ESTIMATE)
        !$omp end critical
        if( present(mskimg) )then
            call bounds_from_mask3D(mskimg%bin2logical(), lb, ub)
        else
            lb = (/ 1, 1, 1/)
            ub = (/ box, box, box /)
        endif
        do k = 1, 3
            if( lb(k) < ext + 1 )   lb(k) = ext+1
            if( ub(k) > box - ext ) ub(k) = box - ext
        enddo
        call weights_img%zero_and_unflag_ft()
        do k = -ext, ext
            do l = -ext, ext
                do m = -ext, ext
                    rad = hyp(real(k), real(l), real(m))
                    val = -rad/(ext + 1) + 1.
                    if( val > 0 ) call weights_img%set_rmat_at(box/2+k+1, box/2+l+1, box/2+m+1, val)
                enddo
            enddo
        enddo
        call weights_img%fft()
        ! searching for the best fourier index from here and generating the optimized filter
        min_sum_odd       = huge(min_sum_odd)
        min_sum_even      = huge(min_sum_even)
        best_ind          = find_start
        opt_odd%opt_val   = 0.
        opt_odd%opt_diff  = 0.
        opt_odd%opt_freq  = 0.
        opt_even%opt_val  = 0.
        opt_even%opt_diff = 0.
        opt_even%opt_freq = 0.
        opt_odd( lb(1):ub(1),lb(2):ub(2),lb(3):ub(3))%opt_diff = huge(min_sum_odd)
        opt_even(lb(1):ub(1),lb(2):ub(2),lb(3):ub(3))%opt_diff = huge(min_sum_odd)
        if( L_BENCH_GLOB )then
            t_tot          = tic()
            rt_filter_all  = 0.
            rt_search_opt  = 0.
            rt_chop_copy   = 0.
            rt_tot         = 0.
            rt_chop_filter = 0.
            rt_chop_sqeu   = 0.
        endif
        do iter_no = 1, params_glob%nsearch
            cur_ind = nint(find_start + (iter_no - 1)*find_stepsz)
            if( L_VERBOSE_GLOB ) write(*,*) '('//int2str(iter_no)//'/'//int2str(params_glob%nsearch)//') current Fourier index = ', cur_ind
            if( L_BENCH_GLOB )then
                t_filter_all = tic()
                t_chop_copy  = tic()
            endif
            ! filtering odd/even
            call  odd%copy_fast( odd_copy_cmat)
            call even%copy_fast(even_copy_cmat)
            if( L_BENCH_GLOB )then
                rt_chop_copy  = rt_chop_copy + toc(t_chop_copy)
                t_chop_filter = tic()
            endif
            call apply_opt_filter_test(odd , cur_ind, find_start, find_stop, cur_fil, .false.)
            call apply_opt_filter_test(even, cur_ind, find_start, find_stop, cur_fil, .true.)
            call batch_ifft_3D(even, odd, in, out, plan_bwd)
            if( L_BENCH_GLOB )then
                rt_chop_filter = rt_chop_filter + toc(t_chop_filter)
                t_chop_sqeu    = tic()
            endif
            call  odd%sqeuclid_matrix(even_copy_rmat, ref_diff_odd_img)
            call even%sqeuclid_matrix( odd_copy_rmat, ref_diff_even_img)
            if( L_BENCH_GLOB )then
                rt_chop_sqeu = rt_chop_sqeu + toc(t_chop_sqeu)
            endif
            if( params_glob%l_match_filt )then
                call  odd%copy_fast(odd_copy_shellnorm)
                call even%copy_fast(even_copy_shellnorm)
                if( L_BENCH_GLOB ) t_chop_filter = tic()
                call apply_opt_filter_test( odd, cur_ind, find_start, find_stop, cur_fil, .false.)
                call apply_opt_filter_test(even, cur_ind, find_start, find_stop, cur_fil, .false.)
                call batch_ifft_3D(even, odd, in, out, plan_bwd)
                if( L_BENCH_GLOB ) rt_chop_filter = rt_chop_filter + toc(t_chop_filter)
            endif
            call  odd%get_rmat_ptr(rmat_odd)
            call even%get_rmat_ptr(rmat_even)
            if( L_BENCH_GLOB )then
                rt_filter_all = rt_filter_all + toc(t_filter_all)
            endif
            if( L_BENCH_GLOB )then
                t_search_opt   = tic()
            endif
            ! do the non-uniform, i.e. optimizing at each voxel
            if( params_glob%l_nonuniform )then
                call  ref_diff_odd_img%set_ft(.false.)
                call ref_diff_even_img%set_ft(.false.)
                call batch_fft_3D(ref_diff_even_img, ref_diff_odd_img, in, out, plan_fwd)
                !$omp parallel workshare
                podd%cmat  =  podd%cmat * pweights%cmat
                peven%cmat = peven%cmat * pweights%cmat
                !$omp end parallel workshare
                ! Add batch ifft here
                call batch_ifft_3D(ref_diff_even_img, ref_diff_odd_img, in, out, plan_bwd)
                !$omp parallel do collapse(3) default(shared) private(k,l,m) schedule(dynamic,CHUNKSZ) proc_bind(close)
                do m = lb(3),ub(3)
                    do l = lb(2),ub(2)
                        do k = lb(1),ub(1)
                            ! opt_diff keeps the minimized cost value at each voxel of the search
                            ! opt_odd  keeps the best voxel of the form B*odd
                            ! opt_even keeps the best voxel of the form B*even
                            if (podd%rmat(k,l,m) < opt_odd(k,l,m)%opt_diff) then
                                opt_odd(k,l,m)%opt_val  =  rmat_odd(k,l,m)
                                opt_odd(k,l,m)%opt_diff = podd%rmat(k,l,m)
                                opt_odd(k,l,m)%opt_freq = cur_ind
                            endif
                            if (peven%rmat(k,l,m) < opt_even(k,l,m)%opt_diff) then
                                opt_even(k,l,m)%opt_val  =  rmat_even(k,l,m)
                                opt_even(k,l,m)%opt_diff = peven%rmat(k,l,m)
                                opt_even(k,l,m)%opt_freq = cur_ind
                            endif
                        enddo
                    enddo
                enddo
                !$omp end parallel do
            else
                ! keep the theta which gives the lowest cost (over all voxels)
                if (sum(podd%rmat) < min_sum_odd) then
                    opt_odd(:,:,:)%opt_val  = rmat_odd(1:box, 1:box, 1:box)
                    opt_odd(:,:,:)%opt_freq = cur_ind
                    min_sum_odd  = sum(podd%rmat)
                    best_ind     = cur_ind
                endif
                if (sum(podd%rmat) < min_sum_even) then
                    opt_even(:,:,:)%opt_val  = rmat_even(1:box, 1:box, 1:box)
                    opt_even(:,:,:)%opt_freq = cur_ind
                    min_sum_even  = sum(podd%rmat)
                endif
            endif
            if( L_VERBOSE_GLOB ) write(*,*) 'current cost (odd) = ', sum(podd%rmat)
            if( L_BENCH_GLOB )then
                rt_search_opt = rt_search_opt + toc(t_search_opt)
            endif
        enddo
        if( L_BENCH_GLOB )then
            rt_tot     = toc(t_tot)
            benchfname = 'OPT_FILTER_BENCH.txt'
            call fopen(fnr, FILE=trim(benchfname), STATUS='REPLACE', action='WRITE')
            write(fnr,'(a)') '*** TIMINGS (s) ***'
            write(fnr,'(a,1x,f9.2)') 'copy_fast            : ', rt_chop_copy
            write(fnr,'(a,1x,f9.2)') 'lp_filter and ifft   : ', rt_chop_filter
            write(fnr,'(a,1x,f9.2)') 'sqeuclid_matrix      : ', rt_chop_sqeu
            write(fnr,'(a,1x,f9.2)') 'filtering            : ', rt_filter_all
            write(fnr,'(a,1x,f9.2)') 'searching/optimizing : ', rt_search_opt
            write(fnr,'(a,1x,f9.2)') 'total time           : ', rt_tot
            write(fnr,'(a)') ''
            write(fnr,'(a)') '*** RELATIVE TIMINGS (%) ***'
            write(fnr,'(a,1x,f9.2)') 'filtering            : ', (rt_filter_all /rt_tot) * 100. 
            write(fnr,'(a,1x,f9.2)') 'searching/optimizing : ', (rt_search_opt /rt_tot) * 100.
            write(fnr,'(a,1x,f9.2)') '% accounted for      : ', ((rt_filter_all+rt_search_opt)/rt_tot) * 100.
            call fclose(fnr)
        endif
        if( L_VERBOSE_GLOB )then
            if( .not. params_glob%l_nonuniform ) write(*,*) 'minimized cost at resolution = ', box*params_glob%smpd/best_ind
        endif
        do k = 1,ldim(1)
            do l = 1,ldim(2)
                do m = 1,ldim(3)
                    call      odd%set_rmat_at(k,l,m,opt_odd( k,l,m)%opt_val)
                    call     even%set_rmat_at(k,l,m,opt_even(k,l,m)%opt_val)
                    call freq_img%set_rmat_at(k,l,m,box*params_glob%smpd/opt_odd(k,l,m)%opt_freq) ! resolution map
                enddo
            enddo
        enddo
        ! output the optimized frequency map to see the nonuniform parts
        if( params_glob%l_nonuniform )then
            file_tag = 'nonuniform_filter_'//trim(params_glob%filter)//'_ext_'//int2str(ext)
        else
            file_tag = 'uniform_filter_'//trim(params_glob%filter)//'_ext_'//int2str(ext)
        endif
        call freq_img%write('opt_resolution_odd_map_'//trim(file_tag)//'.mrc')
        call freq_img%kill
        deallocate(opt_odd, opt_even, cur_fil, weights_3D)
        call odd_copy_rmat%kill
        call odd_copy_cmat%kill
        call odd_copy_shellnorm%kill
        call even_copy_rmat%kill
        call even_copy_cmat%kill
        call even_copy_shellnorm%kill
        call weights_img%kill
        call ref_diff_odd_img%kill
        call ref_diff_even_img%kill
        call fftwf_destroy_plan(plan_fwd)
        call fftwf_destroy_plan(plan_bwd)
        call fftwf_plan_with_nthreads(1)
    end subroutine opt_filter_3D_test

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !! STUFFS BELOW THIS LINE ARE STABLE
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    subroutine opt_2D_filter_sub( even, odd )
        use simple_tvfilter,   only: tvfilter
        use simple_class_frcs, only: class_frcs
        class(image),   intent(inout) :: even(:), odd(:)
        character(len=:), allocatable :: filter, frcs_fname
        type(tvfilter)                :: tvfilt
        type(class_frcs)              :: clsfrcs 
        type(image),      allocatable :: weights_img(:), ref_diff_odd_img(:), ref_diff_even_img(:),&
                                        &odd_copy_rmat(:),  odd_copy_cmat(:),  odd_copy_shellnorm(:),&
                                        &even_copy_rmat(:), even_copy_cmat(:), even_copy_shellnorm(:)
        real,             allocatable :: cur_diff_odd(:,:,:,:), cur_diff_even(:,:,:,:), cur_fil(:,:),&
                                        &weights_2D(:,:,:), frc(:)
        integer,          allocatable :: lplims_hres(:)
        type(opt_vol),    allocatable :: opt_odd(:,:,:,:), opt_even(:,:,:,:)
        real                          :: smpd, lpstart, lp
        integer                       :: iptcl, box, filtsz, ldim(3), ldim_pd(3), smooth_ext, nptcls, hpind_fsc, find
        logical                       :: lpstart_fallback, l_nonuniform, l_phaseplate
        ! init
        ldim         = even(1)%get_ldim()
        filtsz       = even(1)%get_filtsz()
        ldim(3)      = 1 ! because we operate on stacks
        smooth_ext   = params_glob%smooth_ext
        ldim_pd      = ldim + 2 * smooth_ext
        ldim_pd(3)   = 1 ! because we operate on stacks
        box          = ldim_pd(1)
        filter       = trim(params_glob%filter)
        l_nonuniform = params_glob%l_nonuniform
        frcs_fname   = trim(params_glob%frcs)
        smpd         = params_glob%smpd
        nptcls       = size(even)
        lpstart      = params_glob%lpstart
        hpind_fsc    = params_glob%hpind_fsc
        l_phaseplate = params_glob%l_phaseplate

        ! print *, 'ldim         ', ldim(1),    ldim(2),    ldim(3)
        ! print *, 'ldim_pd      ', ldim_pd(1), ldim_pd(2), ldim_pd(3)
        ! print *, 'filtsz       ', filtsz
        ! print *, 'box          ', box
        ! print *, 'filter       ', filter
        ! print *, 'l_nonuniform ', l_nonuniform
        ! print *, 'smooth_ext   ', smooth_ext
        ! print *, 'frcs_fname   ', frcs_fname
        ! print *, 'smpd         ', smpd
        ! print *, 'nptcls       ', nptcls
        ! print *, 'lpstart      ', lpstart
        ! print *, 'hpind_fsc    ', hpind_fsc
        ! print *, 'l_phaseplate ', l_phaseplate

        ! retrieve FRCs
        call clsfrcs%new(nptcls, box, smpd, 1)
        lpstart_fallback = .false.
        if( file_exists(frcs_fname) )then
            call clsfrcs%read(frcs_fname)
        else
            THROW_WARN('Class average FRCs file '//frcs_fname//' does not exist, falling back on lpstart: '//real2str(lpstart))
            lpstart_fallback = .true.
        endif
        filtsz = clsfrcs%get_filtsz()
        ! allocate
        allocate(odd_copy_rmat(nptcls),  odd_copy_cmat(nptcls),  odd_copy_shellnorm(nptcls),&
                &even_copy_rmat(nptcls), even_copy_cmat(nptcls), even_copy_shellnorm(nptcls),&
                &weights_img(nptcls), ref_diff_odd_img(nptcls), ref_diff_even_img(nptcls))
        allocate(cur_diff_odd(box,box,1,nptcls), cur_diff_even(box,box,1,nptcls),&
                &cur_fil(box,nptcls),weights_2D(smooth_ext*2+1,&
                &smooth_ext*2+1,nptcls), frc(filtsz), source=0.)
        allocate(opt_odd(box,box,1,nptcls), opt_even(box,box,1,nptcls), lplims_hres(nptcls))
        ! calculate high-res low-pass limits
        if( lpstart_fallback )then
            lplims_hres = calc_fourier_index(lpstart, box, smpd)
        else
            do iptcl = 1, nptcls
                call clsfrcs%frc_getter(iptcl, hpind_fsc, l_phaseplate, frc)
                ! the below required to retrieve the right Fouirer index limit when we are padding
                find = get_lplim_at_corr(frc, LPLIM_CRIT2D)
                lp   = calc_lowpass_lim(find, box, smpd)               ! box is the padded box size
                lplims_hres(iptcl) = calc_fourier_index(lp, box, smpd) ! this is the Fourier index limit for the padded images
            end do
        endif
        do iptcl = 1, nptcls
            call even(iptcl)%pad_mirr(ldim_pd)
            call odd( iptcl)%pad_mirr(ldim_pd)
            call weights_img(iptcl)%new(ldim_pd, smpd, .false.)
            call ref_diff_odd_img( iptcl)%new(ldim_pd, smpd, .false.)
            call ref_diff_even_img(iptcl)%new(ldim_pd, smpd, .false.)
            call odd_copy_rmat(iptcl)%copy(odd(iptcl))
            call odd_copy_cmat(iptcl)%copy(odd(iptcl))
            call odd_copy_cmat(iptcl)%fft
            call odd_copy_shellnorm(iptcl)%copy(odd(iptcl))
            call odd_copy_shellnorm(iptcl)%shellnorm(return_ft=.true.)
            call even_copy_rmat(iptcl)%copy(even(iptcl))
            call even_copy_cmat(iptcl)%copy(even(iptcl))
            call even_copy_cmat(iptcl)%fft
            call even_copy_shellnorm(iptcl)%copy(even(iptcl))
            call even_copy_shellnorm(iptcl)%shellnorm(return_ft=.true.)
        enddo
        call tvfilt%new(odd(1))
        ! filter
        !$omp parallel do default(shared) private(iptcl) schedule(static) proc_bind(close)
        do iptcl = 1, nptcls
            call opt_filter_2D(odd(iptcl), even(iptcl),&
                            & odd_copy_rmat(iptcl),  odd_copy_cmat(iptcl),  odd_copy_shellnorm(iptcl),&
                            &even_copy_rmat(iptcl), even_copy_cmat(iptcl), even_copy_shellnorm(iptcl),&
                            &tvfilt, cur_diff_odd(:,:,:,iptcl), cur_diff_even(:,:,:,iptcl),&
                            &cur_fil(:,iptcl), weights_2D(:,:,iptcl), lplims_hres(iptcl),&
                            &opt_odd(:,:,:,iptcl), opt_even(:,:,:,iptcl),&
                            &weights_img(iptcl), ref_diff_odd_img(iptcl), ref_diff_even_img(iptcl))
        enddo
        !$omp end parallel do
        ! destruct
        do iptcl = 1, nptcls
            call odd_copy_rmat( iptcl)%kill
            call even_copy_rmat(iptcl)%kill
            call odd_copy_cmat( iptcl)%kill
            call even_copy_cmat(iptcl)%kill
            call odd_copy_shellnorm( iptcl)%kill
            call even_copy_shellnorm(iptcl)%kill
            call weights_img(iptcl)%kill
            call ref_diff_odd_img( iptcl)%kill
            call ref_diff_even_img(iptcl)%kill
            call even(iptcl)%clip_inplace(ldim)
            call odd(iptcl)%clip_inplace(ldim)
        enddo
        call tvfilt%kill()
    end subroutine opt_2D_filter_sub

    ! Compute the value of the Butterworth transfer function of order n(th)
    ! at a given frequency s, with the cut-off frequency fc
    ! SOURCE :
    ! https://en.wikipedia.org/wiki/Butterworth_filter
    function butterworth(s, n, fc) result(val)
        real   , intent(in)  :: s
        integer, intent(in)  :: n
        real   , intent(in)  :: fc
        real                 :: val
        real,    parameter :: AN(11,10) = reshape((/ 1., 1.    ,  0.    ,  0.    ,  0.    ,  0.    ,  0.    ,  0.    ,  0.    , 0.    , 0.,&
                                                    &1., 1.4142,  1.    ,  0.    ,  0.    ,  0.    ,  0.    ,  0.    ,  0.    , 0.    , 0.,&
                                                    &1., 2.    ,  2.    ,  1.    ,  0.    ,  0.    ,  0.    ,  0.    ,  0.    , 0.    , 0.,&
                                                    &1., 2.6131,  3.4142,  2.6131,  1.    ,  0.    ,  0.    ,  0.    ,  0.    , 0.    , 0.,&
                                                    &1., 3.2361,  5.2361,  5.2361,  3.2361,  1.    ,  0.    ,  0.    ,  0.    , 0.    , 0.,&
                                                    &1., 3.8637,  7.4641,  9.1416,  7.4641,  3.8637,  1.    ,  0.    ,  0.    , 0.    , 0.,&
                                                    &1., 4.4940, 10.0978, 14.5918, 14.5918, 10.0978,  4.4940,  1.    ,  0.    , 0.    , 0.,&
                                                    &1., 5.1258, 13.1371, 21.8462, 25.6884, 21.8462, 13.1371,  5.1258,  1.    , 0.    , 0.,&
                                                    &1., 5.7588, 16.5817, 31.1634, 41.9864, 41.9864, 31.1634, 16.5817,  5.7588, 1.    , 0.,&
                                                    &1., 6.3925, 20.4317, 42.8021, 64.8824, 74.2334, 64.8824, 42.8021, 20.4317, 6.3925, 1. /),&
                                                    &(/11,10/))
        complex, parameter :: J = (0, 1) ! Complex identity: j = sqrt(-1)
        complex :: Bn, Kn                ! Normalized Butterworth polynomial, its derivative and its reciprocal
        complex :: js                    ! frequency is multiplied by the complex identity j
        integer :: k
        Bn  = (0., 0.)
        if (s/fc < 100) then
            js  = J*s/fc
            do k = 0, n
                Bn  = Bn + AN(k+1,n)*js**k
            end do
            Kn  = 1/Bn
            val = sqrt(real(Kn)**2 + aimag(Kn)**2)
        else
            val = epsilon(val)
        endif
    end function butterworth

    ! Compute the Butterworth kernel of the order n-th of width w
    ! with the cut-off frequency fc
    ! https://en.wikipedia.org/wiki/Butterworth_filter
    subroutine butterworth_filter(ker, n, fc)
        real,    intent(inout) :: ker(:)
        integer, intent(in)    :: n
        real   , intent(in)    :: fc
        integer :: freq_val
        do freq_val = 1, size(ker)
            ker(freq_val) = butterworth(real(freq_val-1), n, fc)
        enddo        
    end subroutine butterworth_filter

    subroutine apply_opt_filter(img, cur_ind, find_start, find_stop, cur_fil, use_cache, tvfilt_in)
        use simple_tvfilter, only: tvfilter
        class(image), intent(inout) :: img
        integer,      intent(in)    :: cur_ind
        integer,      intent(in)    :: find_start
        integer,      intent(in)    :: find_stop
        real,         intent(inout) :: cur_fil(:)
        logical,      intent(in)    :: use_cache
        type(tvfilter), optional, intent(inout) :: tvfilt_in
        integer, parameter :: BW_ORDER = 8
        real,    parameter :: LAMBDA_MIN = .5 , LAMBDA_MAX = 5.    ! for TV filter
        real               :: param
        type(tvfilter)     :: tvfilt_loc
        select case(params_glob%filt_enum)
            case(FILT_LP)
                call img%lp(cur_ind)
                call img%ifft()
            case(FILT_TV)
                param = LAMBDA_MIN + (cur_ind - find_start)*(LAMBDA_MAX - LAMBDA_MIN)/(find_stop - find_start)
                if( .not. present(tvfilt_in) )then
                    call tvfilt_loc%new
                    if( img%is_2d() )then
                        call tvfilt_loc%apply_filter(img, param)
                    else
                        call tvfilt_loc%apply_filter_3d(img, param)
                    endif
                    call tvfilt_loc%kill
                else
                    if( img%is_2d() )then
                        call tvfilt_in%apply_filter(img, param)
                    else
                        call tvfilt_in%apply_filter_3d(img, param)
                    endif
                endif
                call img%ifft()
            case(FILT_BW8)
                if( .not. use_cache ) call butterworth_filter(cur_fil, BW_ORDER, real(cur_ind))
                call img%apply_filter(cur_fil)
                call img%ifft()
            case DEFAULT
                THROW_HARD('unsupported filter type')
        end select
    end subroutine apply_opt_filter

    subroutine opt_filter_2D(odd, even,&
                            &odd_copy_rmat,  odd_copy_cmat,  odd_copy_shellnorm,&
                            &even_copy_rmat, even_copy_cmat, even_copy_shellnorm,&
                            &tvfilt_in, cur_diff_odd, cur_diff_even, cur_fil, weights_2D, kstop,&
                            &opt_odd, opt_even, weights_img, ref_diff_odd_img, ref_diff_even_img)
        use simple_tvfilter, only: tvfilter
        class(image),   intent(inout) :: odd
        class(image),   intent(inout) :: even
        class(image),   intent(in)    :: odd_copy_rmat,  odd_copy_cmat,  odd_copy_shellnorm,&
                                        &even_copy_rmat, even_copy_cmat, even_copy_shellnorm
        type(tvfilter), intent(inout) :: tvfilt_in
        real,           intent(inout) :: cur_diff_odd(:,:,:), cur_diff_even(:,:,:)
        real,           intent(inout) :: cur_fil(:), weights_2D(:,:)
        integer,        intent(in)    :: kstop
        type(opt_vol),  intent(inout) :: opt_odd(:,:,:), opt_even(:,:,:)
        class(image),   intent(inout) :: weights_img, ref_diff_odd_img, ref_diff_even_img
        integer           :: k,l,m,n, box, dim3, ldim(3), find_start, find_stop, iter_no, ext
        integer           :: best_ind, cur_ind, lb(3), ub(3)
        real              :: min_sum_odd, min_sum_even, rad, find_stepsz, val
        real, pointer     :: rmat_odd(:,:,:), rmat_even(:,:,:)
        type(image_ptr)   :: podd, peven, pweights
        ! init
        ldim              = odd%get_ldim()
        box               = ldim(1)
        dim3              = ldim(3)
        if( dim3 > 1 ) THROW_HARD('This opt_filter_2D is strictly for 2D case only!')
        ext               = params_glob%smooth_ext
        find_stop         = kstop
        find_start        = calc_fourier_index(params_glob%lp_lowres,  box, params_glob%smpd)
        find_stepsz       = real(find_stop - find_start)/(params_glob%nsearch - 1)
        lb                = (/ ext+1  , ext+1  , 1/)
        ub                = (/ box-ext, box-ext, dim3 /)
        ! searching for the best fourier index from here and generating the optimized filter
        min_sum_odd       = huge(min_sum_odd)
        min_sum_even      = huge(min_sum_even)
        best_ind          = find_start
        opt_odd%opt_val   = 0.
        opt_odd%opt_diff  = 0.
        opt_odd%opt_freq  = 0.
        opt_even%opt_val  = 0.
        opt_even%opt_diff = 0.
        opt_even%opt_freq = 0.
        opt_odd( lb(1):ub(1),lb(2):ub(2),lb(3):ub(3))%opt_diff = huge(min_sum_odd)
        opt_even(lb(1):ub(1),lb(2):ub(2),lb(3):ub(3))%opt_diff = huge(min_sum_odd)
        call       weights_img%get_mat_ptrs(pweights)
        call  ref_diff_odd_img%get_mat_ptrs(podd)
        call ref_diff_even_img%get_mat_ptrs(peven)
        call weights_img%zero_and_unflag_ft()
        do m = -ext, ext
            do n = -ext, ext
                rad = hyp(real(m), real(n))
                val = -rad/(ext + 1) + 1.
                if( val > 0 ) call weights_img%set_rmat_at(box/2+m+1, box/2+n+1, 1, val)
            enddo
        enddo
        call weights_img%fft()
        do iter_no = 1, params_glob%nsearch
            cur_ind = nint(find_start + (iter_no - 1)*find_stepsz)
            if( L_VERBOSE_GLOB ) write(*,*) '('//int2str(iter_no)//'/'//int2str(params_glob%nsearch)//') current Fourier index = ', cur_ind
            ! filtering odd
            call odd%copy_fast(odd_copy_cmat)
            call apply_opt_filter(odd, cur_ind, find_start, find_stop, cur_fil, .false., tvfilt_in)
            call odd%sqeuclid_matrix(even_copy_rmat, cur_diff_odd)
            if( params_glob%l_match_filt )then
                call odd%copy_fast(odd_copy_shellnorm)
                call apply_opt_filter(odd, cur_ind, find_start, find_stop, cur_fil, .false., tvfilt_in)
            endif
            call odd%get_rmat_ptr(rmat_odd)
            ! filtering even
            call even%copy_fast(even_copy_cmat)
            call apply_opt_filter(even, cur_ind, find_start, find_stop, cur_fil, .true., tvfilt_in)
            call even%sqeuclid_matrix(odd_copy_rmat, cur_diff_even)
            if( params_glob%l_match_filt )then
                call even%copy_fast(even_copy_shellnorm)
                call apply_opt_filter(even, cur_ind, find_start, find_stop, cur_fil, .false., tvfilt_in)
            endif
            call even%get_rmat_ptr(rmat_even)
            ! do the non-uniform, i.e. optimizing at each voxel
            if( params_glob%l_nonuniform )then                    
                call  ref_diff_odd_img%set_ft(.false.)
                call ref_diff_even_img%set_ft(.false.)
                podd%rmat( :box,:box,:dim3) = cur_diff_odd
                peven%rmat(:box,:box,:dim3) = cur_diff_even
                call  ref_diff_odd_img%fft()
                call ref_diff_even_img%fft()
                podd%cmat  =  podd%cmat * pweights%cmat
                peven%cmat = peven%cmat * pweights%cmat
                call  ref_diff_odd_img%ifft()
                call ref_diff_even_img%ifft()
                do l = lb(2),ub(2)
                    do k = lb(1),ub(1)
                        if (podd%rmat(k,l,1) < opt_odd(k,l,1)%opt_diff) then
                            opt_odd(k,l,1)%opt_val  = rmat_odd(k,l,1)
                            opt_odd(k,l,1)%opt_diff = podd%rmat(k,l,1)
                            opt_odd(k,l,1)%opt_freq = cur_ind
                        endif
                        if (peven%rmat(k,l,1) < opt_even(k,l,1)%opt_diff) then
                            opt_even(k,l,1)%opt_val  = rmat_even(k,l,1)
                            opt_even(k,l,1)%opt_diff = peven%rmat(k,l,1)
                            opt_even(k,l,1)%opt_freq = cur_ind
                        endif
                    enddo
                enddo
            else
                ! keep the theta which gives the lowest cost (over all voxels)
                if (sum(cur_diff_odd) < min_sum_odd) then
                    opt_odd(:,:,:)%opt_val  = rmat_odd(1:box, 1:box, 1:dim3)
                    opt_odd(:,:,:)%opt_freq = cur_ind
                    min_sum_odd  = sum(cur_diff_odd)
                    best_ind     = cur_ind
                endif
                if (sum(cur_diff_even) < min_sum_even) then
                    opt_even(:,:,:)%opt_val  = rmat_even(1:box, 1:box, 1:dim3)
                    opt_even(:,:,:)%opt_freq = cur_ind
                    min_sum_even  = sum(cur_diff_even)
                endif
            endif
            if( L_VERBOSE_GLOB ) write(*,*) 'current cost (odd) = ', sum(cur_diff_odd)
        enddo
        if( L_VERBOSE_GLOB )then
            if( .not. params_glob%l_nonuniform ) write(*,*) 'minimized cost at resolution = ', box*params_glob%smpd/best_ind
        endif
        do k = 1,ldim(1)
            do l = 1,ldim(2)
                call  odd%set_rmat_at(k,l,1,opt_odd( k,l,1)%opt_val)
                call even%set_rmat_at(k,l,1,opt_even(k,l,1)%opt_val)
            enddo
        enddo
    end subroutine opt_filter_2D

    ! 3D optimization(search)-based uniform/nonuniform filter, paralellized version
    subroutine opt_filter_3D(odd, even, mskimg)
        class(image),           intent(inout) :: odd
        class(image),           intent(inout) :: even
        class(image), optional, intent(inout) :: mskimg
        type(image)                ::  odd_copy_rmat,  odd_copy_cmat,  odd_copy_shellnorm, freq_img,&
                                        &even_copy_rmat, even_copy_cmat, even_copy_shellnorm, &
                                        &weights_img, ref_diff_odd_img, ref_diff_even_img
        integer                    :: k,l,m, box, ldim(3), find_start, find_stop, iter_no, fnr
        integer                    :: best_ind, cur_ind, lb(3), ub(3), ext
        real                       :: min_sum_odd, min_sum_even, rad, find_stepsz, val
        character(len=90)          :: file_tag
        integer,       parameter   :: CHUNKSZ = 20
        type(image_ptr)            :: podd, peven, pweights
        real,          pointer     :: rmat_odd(:,:,:), rmat_even(:,:,:)
        real,          allocatable :: cur_diff_odd( :,:,:), cur_diff_even(:,:,:)
        real,          allocatable :: cur_fil(:), weights_3D(:,:,:)
        type(opt_vol), allocatable :: opt_odd(:,:,:), opt_even(:,:,:)
        character(len=LONGSTRLEN)  :: benchfname
        integer(timer_int_kind)    ::  t_tot,  t_filter_all,  t_search_opt,  t_chop_copy,  t_chop_filter,  t_chop_sqeu
        real(timer_int_kind)       :: rt_tot, rt_filter_all, rt_search_opt, rt_chop_copy, rt_chop_filter, rt_chop_sqeu
        ldim        = odd%get_ldim()
        box         = ldim(1)
        ext         = params_glob%smooth_ext
        find_stop   = calc_fourier_index(2. * params_glob%smpd,      box, params_glob%smpd)
        find_start  = calc_fourier_index(     params_glob%lp_lowres, box, params_glob%smpd)
        find_stepsz = real(find_stop - find_start)/(params_glob%nsearch - 1)
        call          freq_img%new(ldim, params_glob%smpd)
        call       weights_img%new(ldim, params_glob%smpd)
        call  ref_diff_odd_img%new(ldim, params_glob%smpd)
        call ref_diff_even_img%new(ldim, params_glob%smpd)
        call       weights_img%get_mat_ptrs(pweights)
        call  ref_diff_odd_img%get_mat_ptrs(podd)
        call ref_diff_even_img%get_mat_ptrs(peven)
        call odd_copy_rmat%copy(odd)
        call odd_copy_cmat%copy(odd)
        call odd_copy_cmat%fft
        call odd_copy_shellnorm%copy(odd)
        call odd_copy_shellnorm%shellnorm(return_ft=.true.)
        call even_copy_rmat%copy(even)
        call even_copy_cmat%copy(even)
        call even_copy_cmat%fft
        call even_copy_shellnorm%copy(even)
        call even_copy_shellnorm%shellnorm(return_ft=.true.)
        allocate(cur_diff_odd( box,box,box), cur_diff_even(box,box,box),&
                &cur_fil(box), weights_3D(ext*2+1,ext*2+1, ext*2+1), source=0.)
        allocate(opt_odd(box,box,box), opt_even(box,box,box))
        if( present(mskimg) )then
            call bounds_from_mask3D(mskimg%bin2logical(), lb, ub)
        else
            lb = (/ 1, 1, 1/)
            ub = (/ box, box, box /)
        endif
        do k = 1, 3
            if( lb(k) < ext + 1 )   lb(k) = ext+1
            if( ub(k) > box - ext ) ub(k) = box - ext
        enddo
        call weights_img%zero_and_unflag_ft()
        do k = -ext, ext
            do l = -ext, ext
                do m = -ext, ext
                    rad = hyp(real(k), real(l), real(m))
                    val = -rad/(ext + 1) + 1.
                    if( val > 0 ) call weights_img%set_rmat_at(box/2+k+1, box/2+l+1, box/2+m+1, val)
                enddo
            enddo
        enddo
        call weights_img%fft()
        ! searching for the best fourier index from here and generating the optimized filter
        min_sum_odd       = huge(min_sum_odd)
        min_sum_even      = huge(min_sum_even)
        best_ind          = find_start
        opt_odd%opt_val   = 0.
        opt_odd%opt_diff  = 0.
        opt_odd%opt_freq  = 0.
        opt_even%opt_val  = 0.
        opt_even%opt_diff = 0.
        opt_even%opt_freq = 0.
        opt_odd( lb(1):ub(1),lb(2):ub(2),lb(3):ub(3))%opt_diff = huge(min_sum_odd)
        opt_even(lb(1):ub(1),lb(2):ub(2),lb(3):ub(3))%opt_diff = huge(min_sum_odd)
        if( L_BENCH_GLOB )then
            t_tot          = tic()
            rt_filter_all  = 0.
            rt_search_opt  = 0.
            rt_chop_copy   = 0.
            rt_tot         = 0.
            rt_chop_filter = 0.
            rt_chop_sqeu   = 0.
        endif
        do iter_no = 1, params_glob%nsearch
            cur_ind = nint(find_start + (iter_no - 1)*find_stepsz)
            if( L_VERBOSE_GLOB ) write(*,*) '('//int2str(iter_no)//'/'//int2str(params_glob%nsearch)//') current Fourier index = ', cur_ind
            if( L_BENCH_GLOB )then
                t_filter_all = tic()
                t_chop_copy  = tic()
            endif
            ! filtering odd/even
            call  odd%copy_fast( odd_copy_cmat)
            call even%copy_fast(even_copy_cmat)
            if( L_BENCH_GLOB )then
                rt_chop_copy  = rt_chop_copy + toc(t_chop_copy)
                t_chop_filter = tic()
            endif
            call apply_opt_filter(odd , cur_ind, find_start, find_stop, cur_fil, .false.)
            call apply_opt_filter(even, cur_ind, find_start, find_stop, cur_fil, .true.)
            if( L_BENCH_GLOB )then
                rt_chop_filter = rt_chop_filter + toc(t_chop_filter)
                t_chop_sqeu    = tic()
            endif
            call  odd%sqeuclid_matrix(even_copy_rmat, cur_diff_odd)
            call even%sqeuclid_matrix( odd_copy_rmat, cur_diff_even)
            if( L_BENCH_GLOB )then
                rt_chop_sqeu = rt_chop_sqeu + toc(t_chop_sqeu)
            endif
            if( params_glob%l_match_filt )then
                call  odd%copy_fast(odd_copy_shellnorm)
                call even%copy_fast(even_copy_shellnorm)
                if( L_BENCH_GLOB ) t_chop_filter = tic()
                call apply_opt_filter( odd, cur_ind, find_start, find_stop, cur_fil, .false.)
                call apply_opt_filter(even, cur_ind, find_start, find_stop, cur_fil, .false.)
                if( L_BENCH_GLOB ) rt_chop_filter = rt_chop_filter + toc(t_chop_filter)
            endif
            call  odd%get_rmat_ptr(rmat_odd)
            call even%get_rmat_ptr(rmat_even)
            if( L_BENCH_GLOB )then
                rt_filter_all = rt_filter_all + toc(t_filter_all)
            endif
            if( L_BENCH_GLOB )then
                t_search_opt   = tic()
            endif
            ! do the non-uniform, i.e. optimizing at each voxel
            if( params_glob%l_nonuniform )then
                call  ref_diff_odd_img%set_ft(.false.)
                call ref_diff_even_img%set_ft(.false.)
                !$omp parallel workshare
                podd%rmat( :box,:box,:box) = cur_diff_odd
                peven%rmat(:box,:box,:box) = cur_diff_even
                !$omp end parallel workshare
                call  ref_diff_odd_img%fft()
                call ref_diff_even_img%fft()
                !$omp parallel workshare
                podd%cmat  =  podd%cmat * pweights%cmat
                peven%cmat = peven%cmat * pweights%cmat
                !$omp end parallel workshare
                call  ref_diff_odd_img%ifft()
                call ref_diff_even_img%ifft()
                !$omp parallel do collapse(3) default(shared) private(k,l,m) schedule(dynamic,CHUNKSZ) proc_bind(close)
                do m = lb(3),ub(3)
                    do l = lb(2),ub(2)
                        do k = lb(1),ub(1)
                            ! opt_diff keeps the minimized cost value at each voxel of the search
                            ! opt_odd  keeps the best voxel of the form B*odd
                            ! opt_even keeps the best voxel of the form B*even
                            if (podd%rmat(k,l,m) < opt_odd(k,l,m)%opt_diff) then
                                opt_odd(k,l,m)%opt_val  =  rmat_odd(k,l,m)
                                opt_odd(k,l,m)%opt_diff = podd%rmat(k,l,m)
                                opt_odd(k,l,m)%opt_freq = cur_ind
                            endif
                            if (peven%rmat(k,l,m) < opt_even(k,l,m)%opt_diff) then
                                opt_even(k,l,m)%opt_val  =  rmat_even(k,l,m)
                                opt_even(k,l,m)%opt_diff = peven%rmat(k,l,m)
                                opt_even(k,l,m)%opt_freq = cur_ind
                            endif
                        enddo
                    enddo
                enddo
                !$omp end parallel do
            else
                ! keep the theta which gives the lowest cost (over all voxels)
                if (sum(cur_diff_odd) < min_sum_odd) then
                    opt_odd(:,:,:)%opt_val  = rmat_odd(1:box, 1:box, 1:box)
                    opt_odd(:,:,:)%opt_freq = cur_ind
                    min_sum_odd  = sum(cur_diff_odd)
                    best_ind     = cur_ind
                endif
                if (sum(cur_diff_even) < min_sum_even) then
                    opt_even(:,:,:)%opt_val  = rmat_even(1:box, 1:box, 1:box)
                    opt_even(:,:,:)%opt_freq = cur_ind
                    min_sum_even  = sum(cur_diff_even)
                endif
            endif
            if( L_VERBOSE_GLOB ) write(*,*) 'current cost (odd) = ', sum(cur_diff_odd)
            if( L_BENCH_GLOB )then
                rt_search_opt = rt_search_opt + toc(t_search_opt)
            endif
        enddo
        if( L_BENCH_GLOB )then
            rt_tot     = toc(t_tot)
            benchfname = 'OPT_FILTER_BENCH.txt'
            call fopen(fnr, FILE=trim(benchfname), STATUS='REPLACE', action='WRITE')
            write(fnr,'(a)') '*** TIMINGS (s) ***'
            write(fnr,'(a,1x,f9.2)') 'copy_fast            : ', rt_chop_copy
            write(fnr,'(a,1x,f9.2)') 'lp_filter and ifft   : ', rt_chop_filter
            write(fnr,'(a,1x,f9.2)') 'sqeuclid_matrix      : ', rt_chop_sqeu
            write(fnr,'(a,1x,f9.2)') 'filtering            : ', rt_filter_all
            write(fnr,'(a,1x,f9.2)') 'searching/optimizing : ', rt_search_opt
            write(fnr,'(a,1x,f9.2)') 'total time           : ', rt_tot
            write(fnr,'(a)') ''
            write(fnr,'(a)') '*** RELATIVE TIMINGS (%) ***'
            write(fnr,'(a,1x,f9.2)') 'filtering            : ', (rt_filter_all /rt_tot) * 100. 
            write(fnr,'(a,1x,f9.2)') 'searching/optimizing : ', (rt_search_opt /rt_tot) * 100.
            write(fnr,'(a,1x,f9.2)') '% accounted for      : ', ((rt_filter_all+rt_search_opt)/rt_tot) * 100.
            call fclose(fnr)
        endif
        if( L_VERBOSE_GLOB )then
            if( .not. params_glob%l_nonuniform ) write(*,*) 'minimized cost at resolution = ', box*params_glob%smpd/best_ind
        endif
        do k = 1,ldim(1)
            do l = 1,ldim(2)
                do m = 1,ldim(3)
                    call      odd%set_rmat_at(k,l,m,opt_odd( k,l,m)%opt_val)
                    call     even%set_rmat_at(k,l,m,opt_even(k,l,m)%opt_val)
                    call freq_img%set_rmat_at(k,l,m,box*params_glob%smpd/opt_odd(k,l,m)%opt_freq) ! resolution map
                enddo
            enddo
        enddo
        ! output the optimized frequency map to see the nonuniform parts
        if( params_glob%l_nonuniform )then
            file_tag = 'nonuniform_filter_'//trim(params_glob%filter)//'_ext_'//int2str(ext)
        else
            file_tag = 'uniform_filter_'//trim(params_glob%filter)//'_ext_'//int2str(ext)
        endif
        call freq_img%write('opt_resolution_odd_map_'//trim(file_tag)//'.mrc')
        call freq_img%kill
        deallocate(opt_odd, opt_even, cur_diff_odd, cur_diff_even, cur_fil, weights_3D)
        call odd_copy_rmat%kill
        call odd_copy_cmat%kill
        call odd_copy_shellnorm%kill
        call even_copy_rmat%kill
        call even_copy_cmat%kill
        call even_copy_shellnorm%kill
        call weights_img%kill
        call ref_diff_odd_img%kill
        call ref_diff_even_img%kill
    end subroutine opt_filter_3D

end module simple_opt_filter
    