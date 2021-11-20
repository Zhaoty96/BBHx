#include "stdio.h"

#include "global.h"
#include "constants.h"
#include "Response.hh"

#define NUM_THREADS_RESPONSE 64

CUDA_CALLABLE_MEMBER
double d_dot_product_1d(double* arr1, double* arr2){
    double out = 0.0;
    for (int i=0; i<3; i++){
        out += arr1[i]*arr2[i];
    }
    return out;
}


CUDA_CALLABLE_MEMBER
cmplx d_vec_H_vec_product(double* arr1, cmplx* H, double* arr2){

    cmplx I(0.0, 1.0);
    cmplx out(0.0, 0.0);
    cmplx trans(0.0, 0.0);
    for (int i=0; i<3; i++){
        trans = cmplx(0.0, 0.0);
        for (int j=0; j<3; j++){
            trans += (H[i*3 + j] * arr2[j]);
        }
        out += arr1[i]*trans;
    }
    return out;
}

CUDA_CALLABLE_MEMBER
double d_sinc(double x){
    if (x == 0.0) return 1.0;
    else return sin(x)/x;
}


/* # Single-link response
# 'full' does include the orbital-delay term, 'constellation' does not
 */
CUDA_CALLABLE_MEMBER
d_Gslr_holder d_EvaluateGslr(double t, double f, cmplx *H, double* k, int response, double* p0){
    // response == 1 is full ,, response anything else is constellation
    //# Trajectories, p0 used only for the full response
    cmplx I(0.0, 1.0);
    cmplx m_I(0.0, -1.0);
    double alpha = Omega0*t; double c = cos(alpha); double s = sin(alpha);
    double a = AU_SI; double e = eorbit;

    //double p0[3] = {a*c, a*s, 0.*t}; // funcp0(t)
    #ifdef __CUDACC__
    CUDA_SHARED double p1L_all[NUM_THREADS_RESPONSE * 3];
    double* p1L = &p1L_all[threadIdx.x * 3];
    CUDA_SHARED double p2L_all[NUM_THREADS_RESPONSE * 3];
    double* p2L = &p2L_all[threadIdx.x * 3];
    CUDA_SHARED double p3L_all[NUM_THREADS_RESPONSE * 3];
    double* p3L = &p3L_all[threadIdx.x * 3];
    CUDA_SHARED double n_all[NUM_THREADS_RESPONSE * 3];
    double* n = &n_all[threadIdx.x * 3];
    #else
    double p1L_all[3];
    double* p1L = &p1L_all[0];
    double p2L_all[3];
    double* p2L = &p2L_all[0];
    double p3L_all[3];
    double* p3L = &p3L_all[0];
    double n_all[3];
    double* n = &n_all[0];

    #endif
    p1L[0] = - a*e*(1 + s*s);
    p1L[1] = a*e*c*s;
    p1L[2] = -a*e*SQRT3*c;


    p2L[0] = a*e/2*(SQRT3*c*s + (1 + s*s));
    p2L[1] = a*e/2*(-c*s - SQRT3*(1 + c*c));
    p2L[2] = -a*e*SQRT3/2*(SQRT3*s - c);


    p3L[0] = a*e/2*(-SQRT3*c*s + (1 + s*s));
    p3L[1] = a*e/2*(-c*s + SQRT3*(1 + c*c));
    p3L[2] = -a*e*SQRT3/2*(-SQRT3*s - c);

    // n1
    n[0] = -1./2*c*s;
    n[1] = 1./2*(1 + c*c);
    n[2] = SQRT3/2*s;

    double kn1= d_dot_product_1d(k, n);
    cmplx n1Hn1 = d_vec_H_vec_product(n, H, n); //np.dot(n1, np.dot(H, n1))

    // n2
    n[0] = c*s - SQRT3*(1 + s*s);
    n[1] = SQRT3*c*s - (1 + c*c);
    n[2] = -SQRT3*s - 3*c;

    for (int i=0; i<3; i++) n[i] = n[i]*1./4.;

    double kn2= d_dot_product_1d(k, n);
    cmplx n2Hn2 = d_vec_H_vec_product(n, H, n); //np.dot(n1, np.dot(H, n1))

    // n3

    n[0] = c*s + SQRT3*(1 + s*s);
    n[1] = -SQRT3*c*s - (1 + c*c);
    n[2] = -SQRT3*s + 3*c;

    for (int i=0; i<3; i++) n[i] = n[i]*1./4.;

    double kn3= d_dot_product_1d(k, n);
    cmplx n3Hn3 = d_vec_H_vec_product(n, H, n); //np.dot(n1, np.dot(H, n1))


    // # Compute intermediate scalar products
    // t scalar case

    double temp1 = p1L[0]+p2L[0]; double temp2 = p1L[1]+p2L[1]; double temp3 = p1L[2]+p2L[2];
    double temp4 = p2L[0]+p3L[0]; double temp5 = p2L[1]+p3L[1]; double temp6 = p2L[2]+p3L[2];
    double temp7 = p3L[0]+p1L[0]; double temp8 = p3L[1]+p1L[1]; double temp9 = p3L[2]+p1L[2];

    p1L[0] = temp1; p1L[1] = temp2; p1L[2] = temp3;  // now p1L_plus_p2L -> p1L
    p2L[0] = temp4; p2L[1] = temp5; p2L[2] = temp6;  // now p2L_plus_p3L -> p2L
    p3L[0] = temp7; p3L[1] = temp8; p3L[2] = temp9;  // now p3L_plus_p1L -> p3L

    double kp1Lp2L = d_dot_product_1d(k, p1L);
    double kp2Lp3L = d_dot_product_1d(k, p2L);
    double kp3Lp1L = d_dot_product_1d(k, p3L);
    double kp0 = d_dot_product_1d(k, p0);

    // # Prefactors - projections are either scalars or vectors
    cmplx factorcexp0;
    if (response==1) factorcexp0 = gcmplx::exp(I*2.*PI*f/C_SI * kp0); // I*2.*PI*f/C_SI * kp0
    else factorcexp0 = cmplx(1.0, 0.0);
    double prefactor = PI*f*L_SI/C_SI;

    cmplx factorcexp12 = gcmplx::exp(I*prefactor * (1.+kp1Lp2L/L_SI)); //prefactor * (1.+kp1Lp2L/L_SI)
    cmplx factorcexp23 = gcmplx::exp(I*prefactor * (1.+kp2Lp3L/L_SI)); //prefactor * (1.+kp2Lp3L/L_SI)
    cmplx factorcexp31 = gcmplx::exp(I*prefactor * (1.+kp3Lp1L/L_SI)); //prefactor * (1.+kp3Lp1L/L_SI)

    cmplx factorsinc12 = d_sinc( prefactor * (1.-kn3));
    cmplx factorsinc21 = d_sinc( prefactor * (1.+kn3));
    cmplx factorsinc23 = d_sinc( prefactor * (1.-kn1));
    cmplx factorsinc32 = d_sinc( prefactor * (1.+kn1));
    cmplx factorsinc31 = d_sinc( prefactor * (1.-kn2));
    cmplx factorsinc13 = d_sinc( prefactor * (1.+kn2));

    // # Compute the Gslr - either scalars or vectors
    d_Gslr_holder Gslr_out;


    cmplx commonfac = I*prefactor*factorcexp0;
    Gslr_out.G12 = commonfac * n3Hn3 * factorsinc12 * factorcexp12;
    Gslr_out.G21 = commonfac * n3Hn3 * factorsinc21 * factorcexp12;
    Gslr_out.G23 = commonfac * n1Hn1 * factorsinc23 * factorcexp23;
    Gslr_out.G32 = commonfac * n1Hn1 * factorsinc32 * factorcexp23;
    Gslr_out.G31 = commonfac * n2Hn2 * factorsinc31 * factorcexp31;
    Gslr_out.G13 = commonfac * n2Hn2 * factorsinc13 * factorcexp31;

    // ### FIXME
    // # G13 = -1j * prefactor * n2Hn2 * factorsinc31 * np.conjugate(factorcexp31)
    return Gslr_out;
}



CUDA_CALLABLE_MEMBER
d_transferL_holder d_TDICombinationFD(d_Gslr_holder Gslr, double f, int TDItag, int rescaled){
    // int TDItag == 1 is XYZ int TDItag == 2 is AET
    // int rescaled == 1 is True int rescaled == 0 is False
    d_transferL_holder transferL;
    cmplx factor, factorAE, factorT;
    cmplx I(0.0, 1.0);
    double x = PI*f*L_SI/C_SI;
    cmplx z = gcmplx::exp(I*2.*x);
    cmplx Xraw, Yraw, Zraw, Araw, Eraw, Traw;
    cmplx factor_convention, point5, c_one, c_two;
    if (TDItag==1){
        // # First-generation TDI XYZ
        // # With x=pifL, factor scaled out: 2I*sin2x*e2ix
        if (rescaled == 1) factor = 1.;
        else factor = 2.*I*sin(2.*x)*z;
        Xraw = Gslr.G21 + z*Gslr.G12 - Gslr.G31 - z*Gslr.G13;
        Yraw = Gslr.G32 + z*Gslr.G23 - Gslr.G12 - z*Gslr.G21;
        Zraw = Gslr.G13 + z*Gslr.G31 - Gslr.G23 - z*Gslr.G32;
        transferL.transferL1 = factor * Xraw;
        transferL.transferL2 = factor * Yraw;
        transferL.transferL3 = factor * Zraw;
        return transferL;
    }

    else{
        //# First-generation TDI AET from X,Y,Z
        //# With x=pifL, factors scaled out: A,E:I*SQRT2*sin2x*e2ix T:2*SQRT2*sin2x*sinx*e3ix
        //# Here we include a factor 2, because the code was first written using the definitions (2) of McWilliams&al_0911 where A,E,T are 1/2 of their LDC definitions
        factor_convention = cmplx(2.,0.0);
        if (rescaled == 1){
            factorAE = cmplx(1., 0.0);
            factorT = cmplx(1., 0.0);
        }
        else{
          factorAE = I*SQRT2*sin(2.*x)*z;
          factorT = 2.*SQRT2*sin(2.*x)*sin(x)*gcmplx::exp(I*3.*x);
        }

        Araw = 0.5 * ( (1.+z)*(Gslr.G31 + Gslr.G13) - Gslr.G23 - z*Gslr.G32 - Gslr.G21 - z*Gslr.G12 );
        Eraw = 0.5*INVSQRT3 * ( (1.-z)*(Gslr.G13 - Gslr.G31) + (2.+z)*(Gslr.G12 - Gslr.G32) + (1.+2.*z)*(Gslr.G21 - Gslr.G23) );
        Traw = INVSQRT6 * ( Gslr.G21 - Gslr.G12 + Gslr.G32 - Gslr.G23 + Gslr.G13 - Gslr.G31);
        transferL.transferL1 = factor_convention * factorAE * Araw;
        transferL.transferL2 = factor_convention * factorAE * Eraw;
        transferL.transferL3 = factor_convention * factorT * Traw;
        return transferL;
    }
}


CUDA_CALLABLE_MEMBER
d_transferL_holder d_JustLISAFDresponseTDI(cmplx *H, double f, double t, double lam, double beta, int TDItag, int order_fresnel_stencil){

    //funck
    CUDA_SHARED double kvec_all[3];
    double* kvec = &kvec_all[0];

    #ifdef __CUDACC__
    CUDA_SHARED double p0_all[NUM_THREADS_RESPONSE * 3];
    double* p0 = &p0_all[threadIdx.x * 3];
    #else
    double p0_all[3];
    double* p0 = &p0_all[0];
    #endif
    kvec[0] = -cos(beta)*cos(lam);
    kvec[1] = -cos(beta)*sin(lam);
    kvec[2] = -sin(beta);

    // funcp0
    double alpha = Omega0*t; double c = cos(alpha); double s = sin(alpha); double a = AU_SI;


    p0[0] = a*c;
    p0[1] = a*s;
    p0[2] = 0.*t;

    // dot kvec with p0
    double kR = d_dot_product_1d(kvec, p0);

    double phaseRdelay = 2.*PI/C_SI *f*kR;

    // going to assume order_fresnel_stencil == 0 for now
    d_Gslr_holder Gslr = d_EvaluateGslr(t, f, H, kvec, 1, p0); // assumes full response
    d_Gslr_holder Tslr; // use same struct because its the same setup
    cmplx m_I(0.0, -1.0); // -1.0 -> mu_I

    // fill Tslr
    Tslr.G12 = Gslr.G12*gcmplx::exp(m_I*phaseRdelay); // really -I*
    Tslr.G21 = Gslr.G21*gcmplx::exp(m_I*phaseRdelay);
    Tslr.G23 = Gslr.G23*gcmplx::exp(m_I*phaseRdelay);
    Tslr.G32 = Gslr.G32*gcmplx::exp(m_I*phaseRdelay);
    Tslr.G31 = Gslr.G31*gcmplx::exp(m_I*phaseRdelay);
    Tslr.G13 = Gslr.G13*gcmplx::exp(m_I*phaseRdelay);

    d_transferL_holder transferL = d_TDICombinationFD(Tslr, f, TDItag, 0);
    transferL.phaseRdelay = phaseRdelay;
    return transferL;
}





 /**
  * Michael Katz added this function.
  * internal function that filles amplitude and phase for a specific frequency and mode.
  */
 CUDA_CALLABLE_MEMBER
 void response_modes(double* phases, double* response_out, int binNum, int mode_i, double* phases_deriv, double* freqs, double phiRef, int ell, int mm, int length, int numBinAll, int numModes,
 cmplx* H, double lam, double beta, double t_ref, int TDItag, int order_fresnel_stencil)
 {

         double eps = 1e-9;

         int start, increment;
         #ifdef __CUDACC__
         start = threadIdx.x;
         increment = blockDim.x;
         #else
         start = 0;
         increment = 1;
         #pragma omp parallel for
         #endif
         for (int i = start; i < length; i += increment)
         {
             int mode_index = (binNum * numModes + mode_i) * length + i;
             int freq_index = binNum * length + i;

             double freq = freqs[freq_index];

             double t_wave_frame = phases_deriv[mode_index];

             d_transferL_holder transferL = d_JustLISAFDresponseTDI(H, freq, t_wave_frame, lam, beta, TDItag, order_fresnel_stencil);

             // transferL1_re
             int start_ind = 0 * numBinAll * numModes * length;
             int start_ind_old = start_ind;
             response_out[start_ind + mode_index] = gcmplx::real(transferL.transferL1);

             // transferL1_im
             start_ind = 1 * numBinAll * numModes * length;
             response_out[start_ind + mode_index] = gcmplx::imag(transferL.transferL1);

             // transferL1_re
             start_ind = 2 * numBinAll * numModes * length;
             response_out[start_ind + mode_index] = gcmplx::real(transferL.transferL2);

             // transferL1_re
             start_ind = 3 * numBinAll * numModes * length;
             response_out[start_ind + mode_index] = gcmplx::imag(transferL.transferL2);

             // transferL1_re
             start_ind = 4 * numBinAll * numModes * length;
             response_out[start_ind + mode_index] = gcmplx::real(transferL.transferL3);

             // transferL1_re
             start_ind = 5 * numBinAll * numModes * length;
             response_out[start_ind + mode_index] = gcmplx::imag(transferL.transferL3);

             // time_freq_corr update
             double phase_change = transferL.phaseRdelay;

             phases[mode_index] +=  phase_change;

         }
}



/*
Calculate spin weighted spherical harmonics
*/
CUDA_CALLABLE_MEMBER
cmplx SpinWeightedSphericalHarmonic(int s, int l, int m, double theta, double phi){
    // l=2
    double fac;
    if ((l==2) && (m==-2)) fac =  sqrt( 5.0 / ( 64.0 * PI ) ) * ( 1.0 - cos( theta ))*( 1.0 - cos( theta ));
    else if ((l==2) && (m==-1)) fac =  sqrt( 5.0 / ( 16.0 * PI ) ) * sin( theta )*( 1.0 - cos( theta ));
    else if ((l==2) && (m==1)) fac =  sqrt( 5.0 / ( 16.0 * PI ) ) * sin( theta )*( 1.0 + cos( theta ));
    else if ((l==2) && (m==2)) fac =  sqrt( 5.0 / ( 64.0 * PI ) ) * ( 1.0 + cos( theta ))*( 1.0 + cos( theta ));
    // l=3
    else if ((l==3) && (m==-3)) fac =  sqrt(21.0/(2.0*PI))*cos(theta/2.0)*pow(sin(theta/2.0),5.0);
    else if ((l==3) && (m==-2)) fac =  sqrt(7.0/(4.0*PI))*(2.0 + 3.0*cos(theta))*pow(sin(theta/2.0),4.0);
    else if ((l==3) && (m==2)) fac =  sqrt(7.0/PI)*pow(cos(theta/2.0),4.0)*(-2.0 + 3.0*cos(theta))/2.0;
    else if ((l==3) && (m==3)) fac =  -sqrt(21.0/(2.0*PI))*pow(cos(theta/2.0),5.0)*sin(theta/2.0);
    // l=4
    else if ((l==4) && (m==-4)) fac =  3.0*sqrt(7.0/PI)*pow(cos(theta/2.0),2.0)*pow(sin(theta/2.0),6.0);
    else if ((l==4) && (m==-3)) fac =  3.0*sqrt(7.0/(2.0*PI))*cos(theta/2.0)*(1.0 + 2.0*cos(theta))*pow(sin(theta/2.0),5.0);

    else if ((l==4) && (m==3)) fac =  -3.0*sqrt(7.0/(2.0*PI))*pow(cos(theta/2.0),5.0)*(-1.0 + 2.0*cos(theta))*sin(theta/2.0);
    else if ((l==4) && (m==4)) fac =  3.0*sqrt(7.0/PI)*pow(cos(theta/2.0),6.0)*pow(sin(theta/2.0),2.0);

    // Result
    cmplx I(0.0, 1.0);
    if (m==0) return cmplx(fac, 0.0);
    else {
        cmplx phaseTerm(m*phi, 0.0);
        return fac * exp(I*phaseTerm);
    }
}



/*
custom dot product in 2d
*/
CUDA_CALLABLE_MEMBER
void dot_product_2d(double* out, double* arr1, int m1, int n1, double* arr2, int m2, int n2){

    // dev and stride are on output
    for (int i=0; i<m1; i++){
        for (int j=0; j<n2; j++){
            out[(i * 3  + j)] = 0.0;
            for (int k=0; k<n1; k++){
                out[(i * 3  + j)] += arr1[i * 3 + k]*arr2[k * 3 + j];
            }
        }
    }
}

/*
Custom dot product in 1d
*/
CUDA_CALLABLE_MEMBER
double dot_product_1d(double arr1[3], double arr2[3]){
    double out = 0.0;
    for (int i=0; i<3; i++){
        out += arr1[i]*arr2[i];
    }
    return out;
}



/**
 * Michael Katz added this function.
 * Main function for calculating PhenomHM in the form used by Michael Katz
 * This is setup to allow for pre-allocation of arrays. Therefore, all arrays
 * should be setup outside of this function.
 */
CUDA_CALLABLE_MEMBER
void responseCore(
    double* phases,
    double* response_out,
    int *ells,
    int *mms,
    double* phases_deriv,
    double* freqs,                      /**< GW frequecny list [Hz] */
    const double phiRef,                        /**< orbital phase at f_ref */
    double inc,
    double lam,
    double beta,
    double psi,
    double t_ref,
    int length,                              /**< reference GW frequency */
    int numModes,
    int binNum,
    int numBinAll,
    int TDItag, int order_fresnel_stencil
)
{

    int ell, mm;

    //// setup response
    CUDA_SHARED double HSplus[9];
    CUDA_SHARED double HScross[9];

    CUDA_SHARED cmplx H_mat[3 * 3];
    CUDA_SHARED double Hplus[3 * 3];
    CUDA_SHARED double Hcross[3 * 3];
    CUDA_SHARED double kvec[3];
    CUDA_SHARED double O1[3 * 3];
    CUDA_SHARED double invO1[3 * 3];
    CUDA_SHARED double out1[3 * 3];

    if THREAD_ZERO
    {
        HSplus[0] = 1.;
        HSplus[1] = 0.;
        HSplus[2] = 0.;
        HSplus[3] = 0.;
        HSplus[4] = -1.;
        HSplus[5] = 0.;
        HSplus[6] = 0.;
        HSplus[7] = 0.;
        HSplus[8] = 0.;

        HScross[0] = 0.;
        HScross[1] = 1.;
        HScross[2] = 0.;
        HScross[3] = 1.;
        HScross[4] = 0.;
        HScross[5] = 0.;
        HScross[6] = 0.;
        HScross[7] = 0.;
        HScross[8] = 0.;


    //##### Based on the f-n by Sylvain   #####
    //CUDA_SHARED double Hplus_all[NUM_THREADS_RESPONSE * 3 * 3];
    //CUDA_SHARED double Hcross_all[NUM_THREADS_RESPONSE * 3 * 3];
    //double* Hplus = &Hplus_all[threadIdx.x * 3 * 3];
    //double* Hcross = &Hcross_all[threadIdx.x * 3 * 3];

    //double* Htemp = (double*) &H_mat[0];  // Htemp alternates with Hplus and Hcross in order to save shared memory: Hp[0], Hc[0], Hp[1], Hc1]
    // Htemp is then transformed into H_mat

    // Wave unit vector

    //double* kvec = &kvec_all[threadIdx.x * 3];
    kvec[0] = -cos(beta)*cos(lam);
    kvec[1] = -cos(beta)*sin(lam);
    kvec[2] = -sin(beta);

    // Compute constant matrices Hplus and Hcross in the SSB frame
    double clambd = cos(lam); double slambd = sin(lam);
    double cbeta = cos(beta); double sbeta = sin(beta);
    double cpsi = cos(psi); double spsi = sin(psi);


    //double* O1 = &O1_all[threadIdx.x * 3 * 3];
    O1[0] = cpsi*slambd-clambd*sbeta*spsi;
    O1[1] = -clambd*cpsi*sbeta-slambd*spsi;
    O1[2] = -cbeta*clambd;
    O1[3] = -clambd*cpsi-sbeta*slambd*spsi;
    O1[4] = -cpsi*sbeta*slambd+clambd*spsi;
    O1[5] = -cbeta*slambd;
    O1[6] = cbeta*spsi;
    O1[7] = cbeta*cpsi;
    O1[8] = -sbeta;


    //double* invO1 = &invO1_all[threadIdx.x * 3 * 3];;
    invO1[0] = cpsi*slambd-clambd*sbeta*spsi;
    invO1[1] = -clambd*cpsi-sbeta*slambd*spsi;
    invO1[2] = cbeta*spsi;
    invO1[3] = -clambd*cpsi*sbeta-slambd*spsi;
    invO1[4] = -cpsi*sbeta*slambd+clambd*spsi;
    invO1[5] = cbeta*cpsi;
    invO1[6] = -cbeta*clambd;
    invO1[7] = -cbeta*slambd;
    invO1[8] = -sbeta;


    //double* out1 = &out1_all[threadIdx.x * 3 * 3];


    // get Hplus
    //if ((threadIdx.x + blockDim.x * blockIdx.x <= 1)) printf("INNER %d %e %e %e\n", threadIdx.x + blockDim.x * blockIdx.x, invO1[0], invO1[1], invO1[6]);

    dot_product_2d(out1, HSplus, 3, 3, invO1, 3, 3);

    dot_product_2d(Hplus, O1, 3, 3, out1, 3, 3);

    // get Hcross
    dot_product_2d(out1, HScross, 3, 3, invO1, 3, 3);
    dot_product_2d(Hcross, O1, 3, 3, out1, 3, 3);

    }
    CUDA_SYNC_THREADS;
    cmplx I = cmplx(0.0, 1.0);
    cmplx Ylm, Yl_m, Yfactorplus, Yfactorcross;

    double trans1, trans2;
    for (int mode_i=0; mode_i<numModes; mode_i++){

        ell = ells[mode_i];
        mm = mms[mode_i];

        if THREAD_ZERO
        {
            Ylm = SpinWeightedSphericalHarmonic(-2, ell, mm, inc, phiRef);
            Yl_m = pow(-1.0, ell)*gcmplx::conj(SpinWeightedSphericalHarmonic(-2, ell, -1*mm, inc, phiRef));
            Yfactorplus = 1./2 * (Ylm + Yl_m);
            //# Yfactorcross = 1j/2 * (Y22 - Y2m2)  ### SB, should be for correct phase conventions
            Yfactorcross = 1./2. * I * (Ylm - Yl_m); //  ### SB, minus because the phase convention is opposite, we'll tace c.c. at the end
            //# Yfactorcross = -1j/2 * (Y22 - Y2m2)  ### SB, minus because the phase convention is opposite, we'll tace c.c. at the end
            //# Yfactorcross = 1j/2 * (Y22 - Y2m2)  ### SB, minus because the phase convention is opposite, we'll tace c.c. at the end
            //# The matrix H_mat is now complex

            //# H_mat = np.conjugate((Yfactorplus*Hplus + Yfactorcross*Hcross))  ### SB: H_ij = H_mat A_22 exp(i\Psi(f))
            for (int i=0; i<3; i++){
                for (int j=0; j<3; j++){
                    trans1 = Hplus[(i * 3 + j)];
                    trans2 = Hcross[(i * 3 + j)];
                    H_mat[(i * 3 + j)] = (Yfactorplus*trans1+ Yfactorcross*trans2);
                }
            }
        }
        CUDA_SYNC_THREADS;

         //if (threadIdx.x == 0) printf("CHECK: %.18e %.18e %.18e\n", inc, phiRef, psi);
        response_modes(phases, response_out, binNum, mode_i, phases_deriv, freqs, phiRef, ell, mm, length, numBinAll, numModes,
        H_mat, lam, beta, t_ref, TDItag, order_fresnel_stencil);

    }
}



////////////
// response
////////////

#define MAX_MODES 6

 CUDA_KERNEL
 void response(
     double* phases,
     double* response_out,
     double* phases_deriv,
     int* ells_in,
     int* mms_in,
     double* freqs,               /**< Frequency points at which to evaluate the waveform (Hz) */
     double* phiRef,                 /**< reference orbital phase (rad) */
     double* inc,
     double* lam,
     double* beta,
     double* psi,
     double* t_ref,
     int TDItag, int order_fresnel_stencil,
     int numModes,
     int length,
     int numBinAll
)
{

    CUDA_SHARED int ells[MAX_MODES];
    CUDA_SHARED int mms[MAX_MODES];

    int start, increment;
    #ifdef __CUDACC__
    start = threadIdx.x;
    increment = blockDim.x;
    #else
    start = 0;
    increment = 1;
    #pragma omp parallel for
    #endif
    for (int i = start; i < numModes; i += increment)
    {
        ells[i] = ells_in[i];
        mms[i] = mms_in[i];
    }

    CUDA_SYNC_THREADS;

    #ifdef __CUDACC__
    start = blockIdx.x;
    increment = gridDim.x;
    #else
    start = 0;
    increment = 1;
    #pragma omp parallel for
    #endif
    for (int binNum = start; binNum < numBinAll; binNum += increment)
    {
        responseCore(phases, response_out, ells, mms, phases_deriv, freqs, phiRef[binNum], inc[binNum], lam[binNum], beta[binNum], psi[binNum], t_ref[binNum], length, numModes, binNum, numBinAll,
        TDItag, order_fresnel_stencil);
    }
}



void LISA_response(
    double* response_out,
    int* ells_in,
    int* mms_in,
    double* freqs,               /**< Frequency points at which to evaluate the waveform (Hz) */
    double* phiRef,                 /**< reference orbital phase (rad) */
    double* inc,
    double* lam,
    double* beta,
    double* psi,
    double* t_ref,
    int TDItag, int order_fresnel_stencil,
    int numModes,
    int length,
    int numBinAll,
    int includesAmps
)
{

    int start_param = includesAmps;  // if it has amps, start_param is 1, else 0

    double* phases = &response_out[start_param * numBinAll * numModes * length];
    double* phases_deriv = &response_out[(start_param + 1) * numBinAll * numModes * length];
    double* response_vals = &response_out[(start_param + 2) * numBinAll * numModes * length];

    int nblocks2 = numBinAll; //std::ceil((numBinAll + NUM_THREADS_RESPONSE -1)/NUM_THREADS_RESPONSE);

    #ifdef __CUDACC__
    response<<<nblocks2, NUM_THREADS_RESPONSE>>>
    (
        phases,
        response_vals,
        phases_deriv,
        ells_in,
        mms_in,
        freqs,               /**< Frequency points at which to evaluate the waveform (Hz) */
        phiRef,                 /**< reference orbital phase (rad) */
        inc,
        lam,
        beta,
        psi,
        t_ref,
        TDItag, order_fresnel_stencil,
        numModes,
        length,
        numBinAll
   );
    cudaDeviceSynchronize();
    gpuErrchk(cudaGetLastError());
    #else
    response
    (
        phases,
        response_vals,
        phases_deriv,
        ells_in,
        mms_in,
        freqs,               /**< Frequency points at which to evaluate the waveform (Hz) */
        phiRef,                 /**< reference orbital phase (rad) */
        inc,
        lam,
        beta,
        psi,
        t_ref,
        TDItag, order_fresnel_stencil,
        numModes,
        length,
        numBinAll
   );
    #endif
}
