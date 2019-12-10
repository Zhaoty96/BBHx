/*  This code was created by Michael Katz.
 *  It is shared under the GNU license (see below).
 *  This code computes the interpolations for the GPU PhenomHM waveform.
 *
 *
 *  Copyright (C) 2019 Michael Katz
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with with program; see the file COPYING. If not, write to the
 *  Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 *  MA  02111-1307  USA
 */

#include "manager.hh"
#include "stdio.h"
#include <assert.h>
#include <cusparse_v2.h>
#include "globalPhenomHM.h"

/*
GPU error checking
*/
#define gpuErrchk_here(ans) { gpuAssert_here((ans), __FILE__, __LINE__); }
inline void gpuAssert_here(cudaError_t code, const char *file, int line, bool abort=true)
{
   if (code != cudaSuccess)
   {
      fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}

/*
CuSparse error checking
*/
#define ERR_NE(X,Y) do { if ((X) != (Y)) { \
                             fprintf(stderr,"Error in %s at %s:%d\n",__func__,__FILE__,__LINE__); \
                             exit(-1);}} while(0)

#define CUDA_CALL(X) ERR_NE((X),cudaSuccess)
#define CUSPARSE_CALL(X) ERR_NE((X),CUSPARSE_STATUS_SUCCESS)
using namespace std;

/*
fill the B array on the GPU for response transfer functions.
*/
CUDA_KERNEL
void fill_B_response(ModeContainer *mode_vals, double *B, int f_length, int num_modes){
    int num_pars = 8;
    for (int mode_i = blockIdx.y * blockDim.y + threadIdx.y;
         mode_i < num_modes;
         mode_i += blockDim.y * gridDim.y){

       for (int i = blockIdx.x * blockDim.x + threadIdx.x;
            i < f_length;
            i += blockDim.x * gridDim.x){

            if (i == f_length - 1){

                B[(i*num_pars*num_modes) + 0*num_modes + mode_i] = 3.0* (mode_vals[mode_i].phaseRdelay[i] - mode_vals[mode_i].phaseRdelay[i-1]);
                B[(i*num_pars*num_modes) + 1*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL1_re[i] - mode_vals[mode_i].transferL1_re[i-1]);
                B[(i*num_pars*num_modes) + 2*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL1_im[i] - mode_vals[mode_i].transferL1_im[i-1]);
                B[(i*num_pars*num_modes) + 3*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL2_re[i] - mode_vals[mode_i].transferL2_re[i-1]);
                B[(i*num_pars*num_modes) + 4*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL2_im[i] - mode_vals[mode_i].transferL2_im[i-1]);
                B[(i*num_pars*num_modes) + 5*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL3_re[i] - mode_vals[mode_i].transferL3_re[i-1]);
                B[(i*num_pars*num_modes) + 6*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL3_im[i] - mode_vals[mode_i].transferL3_im[i-1]);
                B[(i*num_pars*num_modes) + 7*num_modes + mode_i] = 3.0* (mode_vals[mode_i].time_freq_corr[i] - mode_vals[mode_i].time_freq_corr[i-1]);

            } else if (i == 0){
                B[(i*num_pars*num_modes) + 0*num_modes + mode_i] = 3.0* (mode_vals[mode_i].phaseRdelay[1] - mode_vals[mode_i].phaseRdelay[0]);
                B[(i*num_pars*num_modes) + 1*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL1_re[1] - mode_vals[mode_i].transferL1_re[0]);
                B[(i*num_pars*num_modes) + 2*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL1_im[1] - mode_vals[mode_i].transferL1_im[0]);
                B[(i*num_pars*num_modes) + 3*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL2_re[1] - mode_vals[mode_i].transferL2_re[0]);
                B[(i*num_pars*num_modes) + 4*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL2_im[1] - mode_vals[mode_i].transferL2_im[0]);
                B[(i*num_pars*num_modes) + 5*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL3_re[1] - mode_vals[mode_i].transferL3_re[0]);
                B[(i*num_pars*num_modes) + 6*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL3_im[1] - mode_vals[mode_i].transferL3_im[0]);
                B[(i*num_pars*num_modes) + 7*num_modes + mode_i] = 3.0* (mode_vals[mode_i].time_freq_corr[1] - mode_vals[mode_i].time_freq_corr[0]);
            } else{
                B[(i*num_pars*num_modes) + 0*num_modes + mode_i] = 3.0* (mode_vals[mode_i].phaseRdelay[i+1] - mode_vals[mode_i].phaseRdelay[i-1]);
                B[(i*num_pars*num_modes) + 1*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL1_re[i+1] - mode_vals[mode_i].transferL1_re[i-1]);
                B[(i*num_pars*num_modes) + 2*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL1_im[i+1] - mode_vals[mode_i].transferL1_im[i-1]);
                B[(i*num_pars*num_modes) + 3*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL2_re[i+1] - mode_vals[mode_i].transferL2_re[i-1]);
                B[(i*num_pars*num_modes) + 4*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL2_im[i+1] - mode_vals[mode_i].transferL2_im[i-1]);
                B[(i*num_pars*num_modes) + 5*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL3_re[i+1] - mode_vals[mode_i].transferL3_re[i-1]);
                B[(i*num_pars*num_modes) + 6*num_modes + mode_i] = 3.0* (mode_vals[mode_i].transferL3_im[i+1] - mode_vals[mode_i].transferL3_im[i-1]);
                B[(i*num_pars*num_modes) + 7*num_modes + mode_i] = 3.0* (mode_vals[mode_i].time_freq_corr[i+1] - mode_vals[mode_i].time_freq_corr[i-1]);
            }
}
}
}

/*
fill B array on GPU for amp and phase
*/
CUDA_KERNEL void fill_B_wave(ModeContainer *mode_vals, double *B, int f_length, int num_modes){
    int num_pars = 2;
    for (int mode_i = blockIdx.y * blockDim.y + threadIdx.y;
         mode_i < num_modes;
         mode_i += blockDim.y * gridDim.y){

       for (int i = blockIdx.x * blockDim.x + threadIdx.x;
            i < f_length;
            i += blockDim.x * gridDim.x){
    if (i == f_length - 1){
        B[i*num_modes + mode_i] = 3.0* (mode_vals[mode_i].amp[i] - mode_vals[mode_i].amp[i-1]);
        B[(num_modes*f_length) + i*num_modes + mode_i] = 3.0* (mode_vals[mode_i].phase[i] - mode_vals[mode_i].phase[i-1]);
    } else if (i == 0){
        B[i*num_modes + mode_i] = 3.0* (mode_vals[mode_i].amp[1] - mode_vals[mode_i].amp[0]);
        B[(num_modes*f_length) + i*num_modes + mode_i] = 3.0* (mode_vals[mode_i].phase[1] - mode_vals[mode_i].phase[0]);
    } else{
        B[i*num_modes + mode_i] = 3.0* (mode_vals[mode_i].amp[i+1] - mode_vals[mode_i].amp[i-1]);
        B[(num_modes*f_length) + i*num_modes + mode_i] = 3.0* (mode_vals[mode_i].phase[i+1] - mode_vals[mode_i].phase[i-1]);
    }
}
}
}


/*
find spline constants based on matrix solution for response transfer functions.
*/
CUDA_KERNEL
void set_spline_constants_response(ModeContainer *mode_vals, double *B, int f_length, int num_modes){
    double D_i, D_ip1, y_i, y_ip1;
    int num_pars = 8;
    for (int mode_i = blockIdx.y * blockDim.y + threadIdx.y;
         mode_i < num_modes;
         mode_i += blockDim.y * gridDim.y){

       for (int i = blockIdx.x * blockDim.x + threadIdx.x;
            i < f_length-1;
            i += blockDim.x * gridDim.x){

            D_i = B[(i*num_pars*num_modes) + 0*num_modes + mode_i];
            D_ip1 = B[((i+1)*num_pars*num_modes) + 0*num_modes + mode_i];
            y_i = mode_vals[mode_i].phaseRdelay[i];
            y_ip1 = mode_vals[mode_i].phaseRdelay[i+1];
            mode_vals[mode_i].phaseRdelay_coeff_1[i] = D_i;
            mode_vals[mode_i].phaseRdelay_coeff_2[i] = 3.0 * (y_ip1 - y_i) - 2.0*D_i - D_ip1;
            mode_vals[mode_i].phaseRdelay_coeff_3[i] = 2.0 * (y_i - y_ip1) + D_i + D_ip1;

            D_i = B[(i*num_pars*num_modes) + 1*num_modes + mode_i];
            D_ip1 = B[((i+1)*num_pars*num_modes) + 1*num_modes + mode_i];
            y_i = mode_vals[mode_i].transferL1_re[i];
            y_ip1 = mode_vals[mode_i].transferL1_re[i+1];
            mode_vals[mode_i].transferL1_re_coeff_1[i] = D_i;
            mode_vals[mode_i].transferL1_re_coeff_2[i] = 3.0 * (y_ip1 - y_i) - 2.0*D_i - D_ip1;
            mode_vals[mode_i].transferL1_re_coeff_3[i] = 2.0 * (y_i - y_ip1) + D_i + D_ip1;

            D_i = B[(i*num_pars*num_modes) + 2*num_modes + mode_i];
            D_ip1 = B[((i+1)*num_pars*num_modes) + 2*num_modes + mode_i];
            y_i = mode_vals[mode_i].transferL1_im[i];
            y_ip1 = mode_vals[mode_i].transferL1_im[i+1];
            mode_vals[mode_i].transferL1_im_coeff_1[i] = D_i;
            mode_vals[mode_i].transferL1_im_coeff_2[i] = 3.0 * (y_ip1 - y_i) - 2.0*D_i - D_ip1;
            mode_vals[mode_i].transferL1_im_coeff_3[i] = 2.0 * (y_i - y_ip1) + D_i + D_ip1;

            D_i = B[(i*num_pars*num_modes) + 3*num_modes + mode_i];
            D_ip1 = B[((i+1)*num_pars*num_modes) + 3*num_modes + mode_i];
            y_i = mode_vals[mode_i].transferL2_re[i];
            y_ip1 = mode_vals[mode_i].transferL2_re[i+1];
            mode_vals[mode_i].transferL2_re_coeff_1[i] = D_i;
            mode_vals[mode_i].transferL2_re_coeff_2[i] = 3.0 * (y_ip1 - y_i) - 2.0*D_i - D_ip1;
            mode_vals[mode_i].transferL2_re_coeff_3[i] = 2.0 * (y_i - y_ip1) + D_i + D_ip1;

            D_i = B[(i*num_pars*num_modes) + 4*num_modes + mode_i];
            D_ip1 = B[((i+1)*num_pars*num_modes) + 4*num_modes + mode_i];
            y_i = mode_vals[mode_i].transferL2_im[i];
            y_ip1 = mode_vals[mode_i].transferL2_im[i+1];
            mode_vals[mode_i].transferL2_im_coeff_1[i] = D_i;
            mode_vals[mode_i].transferL2_im_coeff_2[i] = 3.0 * (y_ip1 - y_i) - 2.0*D_i - D_ip1;
            mode_vals[mode_i].transferL2_im_coeff_3[i] = 2.0 * (y_i - y_ip1) + D_i + D_ip1;

            D_i = B[(i*num_pars*num_modes) + 5*num_modes + mode_i];
            D_ip1 = B[((i+1)*num_pars*num_modes) + 5*num_modes + mode_i];
            y_i = mode_vals[mode_i].transferL3_re[i];
            y_ip1 = mode_vals[mode_i].transferL3_re[i+1];
            mode_vals[mode_i].transferL3_re_coeff_1[i] = D_i;
            mode_vals[mode_i].transferL3_re_coeff_2[i] = 3.0 * (y_ip1 - y_i) - 2.0*D_i - D_ip1;
            mode_vals[mode_i].transferL3_re_coeff_3[i] = 2.0 * (y_i - y_ip1) + D_i + D_ip1;

            D_i = B[(i*num_pars*num_modes) + 6*num_modes + mode_i];
            D_ip1 = B[((i+1)*num_pars*num_modes) + 6*num_modes + mode_i];
            y_i = mode_vals[mode_i].transferL3_im[i];
            y_ip1 = mode_vals[mode_i].transferL3_im[i+1];
            mode_vals[mode_i].transferL3_im_coeff_1[i] = D_i;
            mode_vals[mode_i].transferL3_im_coeff_2[i] = 3.0 * (y_ip1 - y_i) - 2.0*D_i - D_ip1;
            mode_vals[mode_i].transferL3_im_coeff_3[i] = 2.0 * (y_i - y_ip1) + D_i + D_ip1;

            D_i = B[(i*num_pars*num_modes) + 7*num_modes + mode_i];
            D_ip1 = B[((i+1)*num_pars*num_modes) + 7*num_modes + mode_i];
            y_i = mode_vals[mode_i].time_freq_corr[i];
            y_ip1 = mode_vals[mode_i].time_freq_corr[i+1];
            mode_vals[mode_i].time_freq_coeff_1[i] = D_i;
            mode_vals[mode_i].time_freq_coeff_2[i] = 3.0 * (y_ip1 - y_i) - 2.0*D_i - D_ip1;
            mode_vals[mode_i].time_freq_coeff_3[i] = 2.0 * (y_i - y_ip1) + D_i + D_ip1;
}
}
}

/*
Find spline coefficients after matrix calculation on GPU for amp and phase
*/

CUDA_KERNEL void set_spline_constants_wave(ModeContainer *mode_vals, double *B, int f_length, int num_modes){

    double D_i, D_ip1, y_i, y_ip1;
    int num_pars = 2;
     for (int mode_i = blockIdx.y * blockDim.y + threadIdx.y;
          mode_i < num_modes;
          mode_i += blockDim.y * gridDim.y){

        for (int i = blockIdx.x * blockDim.x + threadIdx.x;
             i < f_length-1;
             i += blockDim.x * gridDim.x){

    D_i = B[i*num_modes + mode_i];
    D_ip1 = B[(i+1)*num_modes + mode_i];
    y_i = mode_vals[mode_i].amp[i];
    y_ip1 = mode_vals[mode_i].amp[i+1];
    mode_vals[mode_i].amp_coeff_1[i] = D_i;
    mode_vals[mode_i].amp_coeff_2[i] = 3.0 * (y_ip1 - y_i) - 2.0*D_i - D_ip1;
    mode_vals[mode_i].amp_coeff_3[i] = 2.0 * (y_i - y_ip1) + D_i + D_ip1;

    D_i = B[(num_modes*f_length) + i*num_modes + mode_i];
    D_ip1 = B[(num_modes*f_length) + (i+1)*num_modes + mode_i];
    y_i = mode_vals[mode_i].phase[i];
    y_ip1 = mode_vals[mode_i].phase[i+1];
    mode_vals[mode_i].phase_coeff_1[i] = D_i;
    mode_vals[mode_i].phase_coeff_2[i] = 3.0 * (y_ip1 - y_i) - 2.0*D_i - D_ip1;
    mode_vals[mode_i].phase_coeff_3[i] = 2.0 * (y_i - y_ip1) + D_i + D_ip1;
}
}
}

/*
Interpolate amp, phase, and response transfer functions on GPU.
*/
CUDA_KERNEL
void interpolate(agcmplx *channel1_out, agcmplx *channel2_out, agcmplx *channel3_out, ModeContainer* old_mode_vals,
    int num_modes, double d_log10f, double *old_freqs, int old_length, double *data_freqs, int data_length, double* t0_arr, double* tRef_arr, double *channel1_ASDinv,
    double *channel2_ASDinv, double *channel3_ASDinv, double t_obs_start, double t_obs_end, int num_walkers){
    //int mode_i = blockIdx.y;

    double f, x, x2, x3, coeff_0, coeff_1, coeff_2, coeff_3;
    double time_check, amp, phase, phaseRdelay, f_min_limit, f_max_limit, t0, tRef, t_break_start, t_break_end;
    double transferL1_re, transferL1_im, transferL2_re, transferL2_im, transferL3_re, transferL3_im;
    agcmplx ampphasefactor;
    agcmplx I = agcmplx(0.0, 1.0);
    int old_ind_below;
    agcmplx trans_complex;
    for (int walker_i = blockIdx.z * blockDim.z + threadIdx.z;
         walker_i < num_walkers;
         walker_i += blockDim.z * gridDim.z){

     f_min_limit = old_freqs[walker_i*old_length];
     f_max_limit = old_freqs[walker_i*old_length + old_length-1];
     t0 = t0_arr[walker_i];
     tRef = tRef_arr[walker_i];
     t_break_start = t0*YRSID_SI + tRef - t_obs_start*YRSID_SI; // t0 and t_obs_start in years. tRef in seconds.
     t_break_end = t0*YRSID_SI + tRef - t_obs_end*YRSID_SI;

    for (int i = blockIdx.x * blockDim.x + threadIdx.x;
         i < data_length;
         i += blockDim.x * gridDim.x){
    //if (mode_i >= num_modes) return;

        channel1_out[walker_i*data_length + i] = agcmplx(0.0, 0.0);
        channel2_out[walker_i*data_length + i] = agcmplx(0.0, 0.0);
        channel3_out[walker_i*data_length + i] = agcmplx(0.0, 0.0);


    /*# if __CUDA_ARCH__>=200
    if (i == 200)
        printf("times: %e %e, %e, %e \n", t0, tRef, t_obs_start, t_break_start);

    #endif*/
    /*for (int i = blockIdx.x * blockDim.x + threadIdx.x;
         i < data_length;
         i += blockDim.x * gridDim.x)
      {*/

    for (int mode_i=0; mode_i<num_modes; mode_i++){
            f = data_freqs[i];
            old_ind_below = floor((log10(f) - log10(old_freqs[walker_i*old_length + 0]))/d_log10f);

            if ((old_ind_below == old_length -1) || (f >= f_max_limit) || (f < f_min_limit) || (old_ind_below >= old_length)){
                return;
            }
            x = (f - old_freqs[walker_i*old_length + old_ind_below])/(old_freqs[walker_i*old_length + old_ind_below+1] - old_freqs[walker_i*old_length + old_ind_below]);
            x2 = x*x;
            x3 = x*x2;
            // interp time frequency to remove less than 0.0
            coeff_0 = old_mode_vals[walker_i*num_modes + mode_i].time_freq_corr[old_ind_below];
            coeff_1 = old_mode_vals[walker_i*num_modes + mode_i].time_freq_coeff_1[old_ind_below];
            coeff_2 = old_mode_vals[walker_i*num_modes + mode_i].time_freq_coeff_2[old_ind_below];
            coeff_3 = old_mode_vals[walker_i*num_modes + mode_i].time_freq_coeff_3[old_ind_below];

            time_check = coeff_0 + (coeff_1*x) + (coeff_2*x2) + (coeff_3*x3);

            if (time_check < t_break_start) {
                continue;
            }

            if ((t_obs_end > 0.0) && (time_check >= t_break_end)){
                continue;
            }

            // interp amplitude
            coeff_0 = old_mode_vals[walker_i*num_modes + mode_i].amp[old_ind_below];
            coeff_1 = old_mode_vals[walker_i*num_modes + mode_i].amp_coeff_1[old_ind_below];
            coeff_2 = old_mode_vals[walker_i*num_modes + mode_i].amp_coeff_2[old_ind_below];
            coeff_3 = old_mode_vals[walker_i*num_modes + mode_i].amp_coeff_3[old_ind_below];

            amp = coeff_0 + (coeff_1*x) + (coeff_2*x2) + (coeff_3*x3);

            if (amp < 1e-40){
                continue;
            }
            // interp phase
            coeff_0 = old_mode_vals[walker_i*num_modes + mode_i].phase[old_ind_below];
            coeff_1 = old_mode_vals[walker_i*num_modes + mode_i].phase_coeff_1[old_ind_below];
            coeff_2 = old_mode_vals[walker_i*num_modes + mode_i].phase_coeff_2[old_ind_below];
            coeff_3 = old_mode_vals[walker_i*num_modes + mode_i].phase_coeff_3[old_ind_below];

            phase  = coeff_0 + (coeff_1*x) + (coeff_2*x2) + (coeff_3*x3);

            coeff_0 = old_mode_vals[walker_i*num_modes + mode_i].phaseRdelay[old_ind_below];
            coeff_1 = old_mode_vals[walker_i*num_modes + mode_i].phaseRdelay_coeff_1[old_ind_below];
            coeff_2 = old_mode_vals[walker_i*num_modes + mode_i].phaseRdelay_coeff_2[old_ind_below];
            coeff_3 = old_mode_vals[walker_i*num_modes + mode_i].phaseRdelay_coeff_3[old_ind_below];

            phaseRdelay  = coeff_0 + (coeff_1*x) + (coeff_2*x2) + (coeff_3*x3);
            ampphasefactor = amp*gcmplx::exp(agcmplx(0.0, phase + phaseRdelay));

            // X or A
            coeff_0 = old_mode_vals[walker_i*num_modes + mode_i].transferL1_re[old_ind_below];
            coeff_1 = old_mode_vals[walker_i*num_modes + mode_i].transferL1_re_coeff_1[old_ind_below];
            coeff_2 = old_mode_vals[walker_i*num_modes + mode_i].transferL1_re_coeff_2[old_ind_below];
            coeff_3 = old_mode_vals[walker_i*num_modes + mode_i].transferL1_re_coeff_3[old_ind_below];

            transferL1_re  = coeff_0 + (coeff_1*x) + (coeff_2*x2) + (coeff_3*x3);

            /*# if __CUDA_ARCH__>=200
            if (i == 15000)
                printf("times: %e, %d, %d, %d, %d, %e, %e, %e, %e, %e, %e\n", f, mode_i, walker_i, old_ind_below, old_length, time_check, t_break_start, t0, tRef, amp, transferL1_re);

            #endif //*/

            coeff_0 = old_mode_vals[walker_i*num_modes + mode_i].transferL1_im[old_ind_below];
            coeff_1 = old_mode_vals[walker_i*num_modes + mode_i].transferL1_im_coeff_1[old_ind_below];
            coeff_2 = old_mode_vals[walker_i*num_modes + mode_i].transferL1_im_coeff_2[old_ind_below];
            coeff_3 = old_mode_vals[walker_i*num_modes + mode_i].transferL1_im_coeff_3[old_ind_below];

            transferL1_im  = coeff_0 + (coeff_1*x) + (coeff_2*x2) + (coeff_3*x3);

            trans_complex = agcmplx(transferL1_re, transferL1_im)* ampphasefactor * channel1_ASDinv[i]; //TODO may be faster to load as complex number with 0.0 for imaginary part

            channel1_out[walker_i*data_length + i] += trans_complex;
            // Y or E
            coeff_0 = old_mode_vals[walker_i*num_modes + mode_i].transferL2_re[old_ind_below];
            coeff_1 = old_mode_vals[walker_i*num_modes + mode_i].transferL2_re_coeff_1[old_ind_below];
            coeff_2 = old_mode_vals[walker_i*num_modes + mode_i].transferL2_re_coeff_2[old_ind_below];
            coeff_3 = old_mode_vals[walker_i*num_modes + mode_i].transferL2_re_coeff_3[old_ind_below];

            transferL2_re  = coeff_0 + (coeff_1*x) + (coeff_2*x2) + (coeff_3*x3);

            coeff_0 = old_mode_vals[walker_i*num_modes + mode_i].transferL2_im[old_ind_below];
            coeff_1 = old_mode_vals[walker_i*num_modes + mode_i].transferL2_im_coeff_1[old_ind_below];
            coeff_2 = old_mode_vals[walker_i*num_modes + mode_i].transferL2_im_coeff_2[old_ind_below];
            coeff_3 = old_mode_vals[walker_i*num_modes + mode_i].transferL2_im_coeff_3[old_ind_below];

            transferL2_im  = coeff_0 + (coeff_1*x) + (coeff_2*x2) + (coeff_3*x3);

            trans_complex = agcmplx(transferL2_re, transferL2_im)* ampphasefactor * channel2_ASDinv[i]; //TODO may be faster to load as complex number with 0.0 for imaginary part

            channel2_out[walker_i*data_length + i] += trans_complex;

            // Z or T
            coeff_0 = old_mode_vals[walker_i*num_modes + mode_i].transferL3_re[old_ind_below];
            coeff_1 = old_mode_vals[walker_i*num_modes + mode_i].transferL3_re_coeff_1[old_ind_below];
            coeff_2 = old_mode_vals[walker_i*num_modes + mode_i].transferL3_re_coeff_2[old_ind_below];
            coeff_3 = old_mode_vals[walker_i*num_modes + mode_i].transferL3_re_coeff_3[old_ind_below];

            transferL3_re  = coeff_0 + (coeff_1*x) + (coeff_2*x2) + (coeff_3*x3);

            coeff_0 = old_mode_vals[walker_i*num_modes + mode_i].transferL3_im[old_ind_below];
            coeff_1 = old_mode_vals[walker_i*num_modes + mode_i].transferL3_im_coeff_1[old_ind_below];
            coeff_2 = old_mode_vals[walker_i*num_modes + mode_i].transferL3_im_coeff_2[old_ind_below];
            coeff_3 = old_mode_vals[walker_i*num_modes + mode_i].transferL3_im_coeff_3[old_ind_below];

            transferL3_im  = coeff_0 + (coeff_1*x) + (coeff_2*x2) + (coeff_3*x3);

            trans_complex = agcmplx(transferL3_re, transferL3_im)* ampphasefactor * channel3_ASDinv[i]; //TODO may be faster to load as complex number with 0.0 for imaginary part

            channel3_out[walker_i*data_length + i] += trans_complex;
    }
}
}
}

/*
Interpolation class initializer
*/

Interpolate::Interpolate(){
    int pass = 0;
}

/*
allocate arrays for interpolation
*/

__host__
void Interpolate::alloc_arrays(int m, int n, double *d_B){
    double *w = new double[m];
    double *a = new double[m];
    double *b = new double[m];
    double *c = new double[m];

    a[0] = 0.0;
    b[0] = 2.0;
    c[0] = 1.0;

    a[m-1] = 1.0;
    b[m-1] = 2.0;
    c[m-1] = 0.0;

    for (int i = 1;
         i < m-1;
         i += 1){
     a[i] = 1.0;
     b[i] = 4.0;
     c[i] = 1.0;
 }

 for (int i=1; i<m; i++){
     w[i] = a[i]/b[i-1];
     b[i] = b[i] - w[i]*c[i-1];
 }

    gpuErrchk_here(cudaMalloc(&d_b, m*sizeof(double)));
    gpuErrchk_here(cudaMemcpy(d_b, b, m*sizeof(double), cudaMemcpyHostToDevice));

    gpuErrchk_here(cudaMalloc(&d_c, m*sizeof(double)));
    gpuErrchk_here(cudaMemcpy(d_c, c, m*sizeof(double), cudaMemcpyHostToDevice));

    gpuErrchk_here(cudaMalloc(&d_w, m*sizeof(double)));
    gpuErrchk_here(cudaMemcpy(d_w, w, m*sizeof(double), cudaMemcpyHostToDevice));

    gpuErrchk_here(cudaMalloc(&d_x, m*n*sizeof(double)));

    delete[] w;
    delete[] a;
    delete[] b;
    delete[] c;

    //CUSPARSE_CALL( cusparseCreate(&handle) );
    //cusparseDgtsv2_nopivot_bufferSizeExt(handle, m, n, d_dl, d_d, d_du, d_B, m, &bufferSizeInBytes);
    //cusparseDestroy(handle);
    //printf("buffer: %d\n", bufferSizeInBytes);

    //cudaMalloc(&pBuffer, bufferSizeInBytes);
}

/*
setup tridiagonal matrix for interpolation solution
*/
CUDA_KERNEL
void setup_d_vals(double *dl, double *d, double *du, int m, int n){
    for (int j = blockIdx.y * blockDim.y + threadIdx.y;
         j < n;
         j += blockDim.y * gridDim.y){

       for (int i = blockIdx.x * blockDim.x + threadIdx.x;
            i < m;
            i += blockDim.x * gridDim.x){
    if (i == 0){
        dl[j*m + 0] = 0.0;
        d[j*m + 0] = 2.0;
        du[j*m + 0] = 1.0;
    } else if (i == m - 1){
        dl[j*m + m-1] = 1.0;
        d[j*m + m-1] = 2.0;
        du[j*m + m-1] = 0.0;
    } else{
        dl[j*m + i] = 1.0;
        d[j*m + i] = 4.0;
        du[j*m + i] = 1.0;
    }
}
}
}

/*
solve matrix solution for tridiagonal matrix for cublic spline.
*/
void Interpolate::prep(double *B, int m_, int n_, int to_gpu_){
    m = m_;
    n = n_;
    to_gpu = to_gpu_;
    int NUM_THREADS = 256;

    int num_blocks = std::ceil((m + NUM_THREADS -1)/NUM_THREADS);
    //setup_d_vals<<<dim3(num_blocks, n), NUM_THREADS>>>(d_dl, d_d, d_du, m, n);
    cudaDeviceSynchronize();
    gpuErrchk_here(cudaGetLastError());
    Interpolate::gpu_fit_constants(B);
}

CUDA_KERNEL
void gpu_fit_constants_serial(int m, int n, double *w, double *b, double *c, double *d_in, double *x_in){

    //double *x, *d;
    for (int j = blockIdx.x * blockDim.x + threadIdx.x;
         j < n;
         j += blockDim.x * gridDim.x){

        # pragma unroll
        for (int i=2; i<m; i++){
            //printf("%d\n", i);
            d_in[i*n + j] = d_in[i*n + j] - w[i]*d_in[(i-1)*n + j];
            //printf("%lf, %lf, %lf\n", w[i], d[i], b[i]);
        }

        x_in[(m-1)*n + j] = d_in[(m-1)*n + j]/b[m-1];
        d_in[(m-1)*n + j] = x_in[(m-1)*n + j];
        # pragma unroll
        for (int i=(m-2); i>=0; i--){
            x_in[i*n + j] = (d_in[i*n + j] - c[i]*x_in[(i+1)*n + j])/b[i];
            d_in[i*n + j] = x_in[i*n + j];
        }
    }
}

/*
Use cuSparse to perform matrix calcuation.
*/
__host__ void Interpolate::gpu_fit_constants(double *B){
    //CUSPARSE_CALL( cusparseCreate(&handle) );
    //cusparseStatus_t status = cusparseDgtsv2_nopivot(handle, m, n, d_dl, d_d, d_du, B, m, pBuffer);
    //if (status !=  CUSPARSE_STATUS_SUCCESS) assert(0);
    //cusparseDestroy(handle);
    int NUM_THREADS = 256;
    int num_blocks = std::ceil((n + NUM_THREADS -1)/NUM_THREADS);
    gpu_fit_constants_serial<<<num_blocks, NUM_THREADS>>>(m, n, d_w, d_b, d_c, B, d_x);
    cudaDeviceSynchronize();
    gpuErrchk_here(cudaGetLastError());

}


/*
Deallocate
*/
__host__ Interpolate::~Interpolate(){
    cudaFree(d_b);
    cudaFree(d_c);
    cudaFree(d_w);
    cudaFree(d_x);
    cudaFree(pBuffer);
}
