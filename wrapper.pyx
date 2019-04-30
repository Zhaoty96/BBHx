import numpy as np
cimport numpy as np

assert sizeof(int) == sizeof(np.int32_t)

cdef extern from "src/manager.hh":
    cdef cppclass GPUPhenomHMwrap "GPUPhenomHM":
        GPUPhenomHMwrap(int,
        np.uint32_t *,
        np.uint32_t *,
        int,
        int,
        int,
        np.complex128_t *, int, np.float64_t*, np.float64_t*, np.float64_t*)
        void cpu_gen_PhenomHM(np.float64_t *, int,
                            double,
                            double,
                            double,
                            double,
                            double,
                            double,
                            double,
                            double,
                            double)

        void gpu_gen_PhenomHM(np.float64_t *, int,
                            double,
                            double,
                            double,
                            double,
                            double,
                            double,
                            double,
                            double,
                            double)

        void add_interp(int)

        void gpu_setup_interp_wave()
        void cpu_setup_interp_wave()

        void gpu_perform_interp(double, double, int)
        void cpu_perform_interp(double, double, int)

        void cpu_LISAresponseFD(double, double, double, double, double, double, double, int)
        void gpu_LISAresponseFD(double, double, double, double, double, double, double, int)

        void gpu_setup_interp_response()
        void cpu_setup_interp_response()

        void Likelihood(int, np.float64_t*)
        void Get_Waveform(np.complex128_t*, np.complex128_t*, np.complex128_t*)
        void gpu_Get_Waveform(np.complex128_t*, np.complex128_t*, np.complex128_t*)

cdef class GPUPhenomHM:
    cdef GPUPhenomHMwrap* g
    cdef int num_modes
    cdef int f_dim
    cdef int data_length
    cdef int interp_length

    def __cinit__(self, max_length,
     np.ndarray[ndim=1, dtype=np.uint32_t] l_vals,
     np.ndarray[ndim=1, dtype=np.uint32_t] m_vals,
     to_gpu, to_interp, np.ndarray[ndim=1, dtype=np.complex128_t] data_stream,
     np.ndarray[ndim=1, dtype=np.float64_t] X_ASDinv,
     np.ndarray[ndim=1, dtype=np.float64_t] Y_ASDinv,
     np.ndarray[ndim=1, dtype=np.float64_t] Z_ASDinv):
        self.num_modes = len(l_vals)
        self.data_length = len(data_stream)
        self.g = new GPUPhenomHMwrap(max_length,
        &l_vals[0],
        &m_vals[0],
        self.num_modes,
        to_gpu, to_interp, &data_stream[0], self.data_length, &X_ASDinv[0], &Y_ASDinv[0], &Z_ASDinv[0])

    def cpu_gen_PhenomHM(self, np.ndarray[ndim=1, dtype=np.float64_t] freqs,
                        m1, #solar masses
                        m2, #solar masses
                        chi1z,
                        chi2z,
                        distance,
                        inclination,
                        phiRef,
                        deltaF,
                        f_ref):

        self.f_dim = len(freqs)
        self.g.cpu_gen_PhenomHM(&freqs[0], self.f_dim,
                                m1, #solar masses
                                m2, #solar masses
                                chi1z,
                                chi2z,
                                distance,
                                inclination,
                                phiRef,
                                deltaF,
                                f_ref)

    def gpu_gen_PhenomHM(self, np.ndarray[ndim=1, dtype=np.float64_t] freqs,
                        m1, #solar masses
                        m2, #solar masses
                        chi1z,
                        chi2z,
                        distance,
                        inclination,
                        phiRef,
                        deltaF,
                        f_ref):

        self.f_dim = len(freqs)
        self.g.gpu_gen_PhenomHM(&freqs[0], self.f_dim,
                                m1, #solar masses
                                m2, #solar masses
                                chi1z,
                                chi2z,
                                distance,
                                inclination,
                                phiRef,
                                deltaF,
                                f_ref)

    def add_interp(self, interp_length):
        self.interp_length = interp_length
        self.g.add_interp(interp_length)
        return

    def gpu_setup_interp_wave(self):
        self.g.gpu_setup_interp_wave()
        return

    def cpu_setup_interp_wave(self):
        self.g.cpu_setup_interp_wave()
        return

    def gpu_LISAresponseFD(self, inc, lam, beta, psi, t0, tRef, merger_freq, TDItag):
        self.g.gpu_LISAresponseFD(inc, lam, beta, psi, t0, tRef, merger_freq, TDItag)
        return

    def cpu_LISAresponseFD(self, inc, lam, beta, psi, t0, tRef, merger_freq, TDItag):
        self.g.cpu_LISAresponseFD(inc, lam, beta, psi, t0, tRef, merger_freq, TDItag)
        return

    def gpu_setup_interp_response(self):
        self.g.gpu_setup_interp_response()
        return

    def cpu_setup_interp_response(self):
        self.g.cpu_setup_interp_response()
        return

    def gpu_perform_interp(self, f_min, df, length_new):
        self.g.gpu_perform_interp(f_min, df, length_new)
        return

    def cpu_perform_interp(self, f_min, df, length_new):
        self.g.cpu_perform_interp(f_min, df, length_new)
        return

    def Likelihood(self, length):
        cdef np.ndarray[ndim=1, dtype=np.float64_t] like_out_ = np.zeros((2,), dtype=np.float64)
        self.g.Likelihood(length, &like_out_[0])
        return like_out_

    def Get_Waveform(self):
        cdef np.ndarray[ndim=1, dtype=np.complex128_t] X_ = np.zeros((self.interp_length*self.num_modes,), dtype=np.complex128)
        cdef np.ndarray[ndim=1, dtype=np.complex128_t] Y_ = np.zeros((self.interp_length*self.num_modes,), dtype=np.complex128)
        cdef np.ndarray[ndim=1, dtype=np.complex128_t] Z_ = np.zeros((self.interp_length*self.num_modes,), dtype=np.complex128)

        self.g.Get_Waveform(&X_[0], &Y_[0], &Z_[0])

        return (X_.reshape(self.num_modes, self.interp_length), Y_.reshape(self.num_modes, self.interp_length), Z_.reshape(self.num_modes, self.interp_length))

    def gpu_Get_Waveform(self):
        cdef np.ndarray[ndim=1, dtype=np.complex128_t] X_ = np.zeros((self.interp_length*self.num_modes,), dtype=np.complex128)
        cdef np.ndarray[ndim=1, dtype=np.complex128_t] Y_ = np.zeros((self.interp_length*self.num_modes,), dtype=np.complex128)
        cdef np.ndarray[ndim=1, dtype=np.complex128_t] Z_ = np.zeros((self.interp_length*self.num_modes,), dtype=np.complex128)

        self.g.gpu_Get_Waveform(&X_[0], &Y_[0], &Z_[0])

        return (X_.reshape(self.num_modes, self.interp_length), Y_.reshape(self.num_modes, self.interp_length), Z_.reshape(self.num_modes, self.interp_length))
