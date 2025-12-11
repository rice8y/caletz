use std::f64::consts::PI;
use std::fmt::Write;
use wasm_minimal_protocol::*;

initiate_protocol!();

// Complex number operations - optimized with inline
#[derive(Clone, Copy)]
struct Complex {
    re: f64,
    im: f64,
}

impl Complex {
    #[inline(always)]
    const fn new(re: f64, im: f64) -> Self {
        Complex { re, im }
    }

    #[inline(always)]
    fn add(self, other: Self) -> Self {
        Complex::new(self.re + other.re, self.im + other.im)
    }

    #[inline(always)]
    fn sub(self, other: Self) -> Self {
        Complex::new(self.re - other.re, self.im - other.im)
    }

    #[inline(always)]
    fn mul(self, other: Self) -> Self {
        Complex::new(
            self.re * other.re - self.im * other.im,
            self.re * other.im + self.im * other.re,
        )
    }

    #[inline(always)]
    fn scale(self, s: f64) -> Self {
        Complex::new(self.re * s, self.im * s)
    }

    #[inline(always)]
    fn exp(theta: f64) -> Self {
        let (sin, cos) = theta.sin_cos();
        Complex::new(cos, sin)
    }

    #[inline(always)]
    fn exp_full(a: f64, b: f64) -> Self {
        let r = a.exp();
        let (sin, cos) = b.sin_cos();
        Complex::new(r * cos, r * sin)
    }

    #[inline]
    fn pow(self, p: f64) -> Self {
        let r_sq = self.re * self.re + self.im * self.im;
        if r_sq < 1e-20 {
            return Complex::new(0.0, 0.0);
        }
        let r = r_sq.sqrt();
        let theta = self.im.atan2(self.re);
        let rp = r.powf(p);
        let phi = theta * p;
        let (sin, cos) = phi.sin_cos();
        Complex::new(rp * cos, rp * sin)
    }
}

// U functions - inline for performance
#[inline]
fn u1(a: f64, b: f64) -> Complex {
    let exp1 = Complex::exp_full(a, b);
    let exp2 = Complex::exp_full(-a, -b);
    exp1.add(exp2).scale(0.5)
}

#[inline]
fn u3(a: f64, b: f64) -> Complex {
    let exp1 = Complex::exp_full(a, b);
    let exp2 = Complex::exp_full(-a, -b);
    exp1.sub(exp2).scale(0.5)
}

// Coordinate transformation - inline and precompute values
#[inline]
fn cy_coordinate(a: f64, b: f64, n_inv: f64, phase1: Complex, phase2: Complex, alpha_cos: f64, alpha_sin: f64) -> (f64, f64, f64) {
    let u1_val = u1(a, b).pow(n_inv);
    let u3_val = u3(a, b).pow(n_inv);
    
    let z1 = phase1.mul(u1_val);
    let z2 = phase2.mul(u3_val);
    
    (
        z1.re,
        z2.re,
        z1.im * alpha_cos + z2.im * alpha_sin,
    )
}

// Generate mesh for a single branch - optimized with precomputed values
fn generate_branch_mesh(
    n: u32,
    k1: u32,
    k2: u32,
    alpha: f64,
    subdivisions: u32,
) -> Vec<f64> {
    let capacity = ((subdivisions + 1) * (subdivisions + 1) * 3) as usize;
    let mut mesh = Vec::with_capacity(capacity);
    
    let step = 1.0 / subdivisions as f64;
    let n_inv = 2.0 / n as f64;
    
    // Precompute phase factors
    let phase1 = Complex::exp(2.0 * PI * k1 as f64 / n as f64);
    let phase2 = Complex::exp(2.0 * PI * k2 as f64 / n as f64);
    
    // Precompute alpha trigonometry
    let (alpha_sin, alpha_cos) = alpha.sin_cos();

    // Precompute PI/2 to avoid repeated multiplication
    let pi_half = PI * 0.5;

    for i in 0..=subdivisions {
        let u = i as f64 * step;
        let a = u * pi_half;

        for j in 0..=subdivisions {
            let v = j as f64 * step;
            let b = (v - 0.5) * PI;
            let (x, y, z) = cy_coordinate(a, b, n_inv, phase1, phase2, alpha_cos, alpha_sin);
            
            mesh.push(x);
            mesh.push(y);
            mesh.push(z);
        }
    }

    mesh
}

// Generate all meshes for all branches - optimized allocation
fn generate_all_meshes(n: u32, alpha: f64, subdivisions: u32) -> Vec<f64> {
    let points_per_mesh = ((subdivisions + 1) * (subdivisions + 1) * 3) as usize;
    let total_meshes = (n * n) as usize;
    let mut all_meshes = Vec::with_capacity(points_per_mesh * total_meshes);

    for k1 in 0..n {
        for k2 in 0..n {
            let mesh = generate_branch_mesh(n, k1, k2, alpha, subdivisions);
            all_meshes.extend_from_slice(&mesh);
        }
    }

    all_meshes
}

// WASM plugin interface - returns data as comma-separated string
// Optimized string building
#[wasm_func]
pub fn generate_calabi_yau(input: &[u8]) -> Vec<u8> {
    // Parse input
    let input_str = match std::str::from_utf8(input) {
        Ok(s) => s,
        Err(_) => return b"Error: invalid UTF-8".to_vec(),
    };
    
    let parts: Vec<&str> = input_str.trim().split(',').collect();
    if parts.len() != 3 {
        return b"Error: expected 3 parameters (n,alpha,subdivisions)".to_vec();
    }
    
    let n: u32 = match parts[0].parse() { 
        Ok(v) => v, 
        Err(_) => return b"Error: invalid n".to_vec() 
    };
    let alpha: f64 = match parts[1].parse() { 
        Ok(v) => v, 
        Err(_) => return b"Error: invalid alpha".to_vec() 
    };
    let subdivisions: u32 = match parts[2].parse() { 
        Ok(v) => v, 
        Err(_) => return b"Error: invalid subdivisions".to_vec() 
    };

    // Generate meshes
    let meshes = generate_all_meshes(n, alpha, subdivisions);

    // Compute z-min and z-max in single pass
    let mut z_min = f64::INFINITY;
    let mut z_max = f64::NEG_INFINITY;
    
    // Optimize by iterating with step
    for i in (2..meshes.len()).step_by(3) {
        let z = meshes[i];
        if z < z_min { z_min = z; }
        if z > z_max { z_max = z; }
    }

    // Preallocate string with estimated capacity
    // Each float is ~20 chars average, plus commas
    let estimated_capacity = meshes.len() * 21 + 50;
    let mut output = String::with_capacity(estimated_capacity);
    
    // Build output string efficiently
    for (i, value) in meshes.iter().enumerate() {
        if i > 0 { 
            output.push(','); 
        }
        let _ = write!(output, "{}", value);
    }
    
    output.push(',');
    let _ = write!(output, "{}", z_min);
    output.push(',');
    let _ = write!(output, "{}", z_max);

    output.into_bytes()
}