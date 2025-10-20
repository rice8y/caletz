#import "requirements.typ": *

// Complex number operations
#let cx-new(re, im) = (re: re, im: im)
#let cx-add(a, b) = cx-new(a.re + b.re, a.im + b.im)
#let cx-sub(a, b) = cx-new(a.re - b.re, a.im - b.im)
#let cx-mul(a, b) = cx-new(
  a.re * b.re - a.im * b.im,
  a.re * b.im + a.im * b.re
)
#let cx-exp(theta) = cx-new(calc.cos(theta), calc.sin(theta))
#let cx-exp-full(a, b) = {
  let r = calc.exp(a)
  cx-new(r * calc.cos(b), r * calc.sin(b))
}
#let cx-pow(z, p) = {
  let r = calc.sqrt(z.re * z.re + z.im * z.im)
  if r < 1e-10 { return cx-new(0, 0) }
  let theta = calc.atan2(z.im, z.re)
  let rp = calc.pow(r, p)
  let phi = theta * p
  cx-new(rp * calc.cos(phi), rp * calc.sin(phi))
}
#let cx-scale(z, s) = cx-new(z.re * s, z.im * s)

// U functions
#let u1(a, b) = {
  let exp1 = cx-exp-full(a, b)
  let exp2 = cx-exp-full(-a, -b)
  cx-scale(cx-add(exp1, exp2), 0.5)
}
#let u3(a, b) = {
  let exp1 = cx-exp-full(a, b)
  let exp2 = cx-exp-full(-a, -b)
  cx-scale(cx-sub(exp1, exp2), 0.5)
}

// Coordinate transformation
#let cy-coordinate(a, b, n, k1, k2, alpha) = {
  let U1 = cx-pow(u1(a, b), 2.0 / n)
  let U3 = cx-pow(u3(a, b), 2.0 / n)
  let phase1 = cx-exp(2.0 * calc.pi * k1 / n)
  let phase2 = cx-exp(2.0 * calc.pi * k2 / n)
  let z1 = cx-mul(phase1, U1)
  let z2 = cx-mul(phase2, U3)
  (
    x: z1.re,
    y: z2.re,
    z: z1.im * calc.cos(alpha) + z2.im * calc.sin(alpha)
  )
}

// Colormap functions
#let cmap-jet(x, y, z, x-lo, x-hi, y-lo, y-hi, z-lo, z-hi) = {
  let t = if calc.abs(z-hi - z-lo) > 1e-10 { 
    (z - z-lo) / (z-hi - z-lo) 
  } else { 0.5 }
  t = calc.max(0, calc.min(1, t))
  
  if t < 0.25 {
    rgb(0, 0, int(255 * (0.5 + 2 * t)))
  } else if t < 0.5 {
    rgb(0, int(255 * (4 * t - 1)), 255)
  } else if t < 0.75 {
    rgb(int(255 * (4 * t - 2)), 255, int(255 * (3 - 4 * t)))
  } else {
    rgb(255, int(255 * (4 - 4 * t)), 0)
  }
}

#let cmap-viridis(x, y, z, x-lo, x-hi, y-lo, y-hi, z-lo, z-hi) = {
  let t = if calc.abs(z-hi - z-lo) > 1e-10 { 
    (z - z-lo) / (z-hi - z-lo) 
  } else { 0.5 }
  t = calc.max(0, calc.min(1, t))
  rgb(int(68 + t * (253 - 68)), int(1 + t * (231 - 1)), int(84 + t * (37 - 84)))
}

#let cmap-plasma(x, y, z, x-lo, x-hi, y-lo, y-hi, z-lo, z-hi) = {
  let t = if calc.abs(z-hi - z-lo) > 1e-10 { 
    (z - z-lo) / (z-hi - z-lo) 
  } else { 0.5 }
  t = calc.max(0, calc.min(1, t))
  rgb(int(13 + t * (240 - 13)), int(8 + t * (249 - 8)), int(135 + t * (33 - 135)))
}

#let cmap-cool(x, y, z, x-lo, x-hi, y-lo, y-hi, z-lo, z-hi) = {
  let t = if calc.abs(z-hi - z-lo) > 1e-10 { 
    (z - z-lo) / (z-hi - z-lo) 
  } else { 0.5 }
  t = calc.max(0, calc.min(1, t))
  rgb(int(t * 255), int((1 - t) * 255), 255).lighten(20%)
}

#let cmap-hot(x, y, z, x-lo, x-hi, y-lo, y-hi, z-lo, z-hi) = {
  let t = if calc.abs(z-hi - z-lo) > 1e-10 { 
    (z - z-lo) / (z-hi - z-lo) 
  } else { 0.5 }
  t = calc.max(0, calc.min(1, t))
  let r = calc.min(1, t * 3)
  let g = calc.max(0, calc.min(1, t * 3 - 1))
  let b = calc.max(0, calc.min(1, t * 3 - 2))
  rgb(int(r * 255), int(g * 255), int(b * 255))
}

#let get-colormap(name) = {
  if name == "viridis" { cmap-viridis }
  else if name == "plasma" { cmap-plasma }
  else if name == "cool" { cmap-cool }
  else if name == "hot" { cmap-hot }
  else { cmap-jet }
}

// Generate surface mesh for a single branch
#let generate-branch-mesh(n, k1, k2, alpha, subdivisions) = {
  let mesh = ()
  let step = 1.0 / subdivisions
  
  for i in range(subdivisions + 1) {
    let row = ()
    let u = i * step
    let a = u * calc.pi / 2
    
    for j in range(subdivisions + 1) {
      let v = j * step
      let b = (v - 0.5) * calc.pi
      let coord = cy-coordinate(a, b, n, k1, k2, alpha)
      row.push(coord)
    }
    mesh.push(row)
  }
  mesh
}

// Render a mesh as triangulated surface using CeTZ
#let render-mesh(mesh, color-func, z-lo, z-hi) = {
  import cetz.draw: *
  
  let rows = mesh.len()
  let cols = mesh.at(0).len()
  
  // Draw triangulated quads
  for i in range(rows - 1) {
    for j in range(cols - 1) {
      let p00 = mesh.at(i).at(j)
      let p01 = mesh.at(i).at(j + 1)
      let p10 = mesh.at(i + 1).at(j)
      let p11 = mesh.at(i + 1).at(j + 1)
      
      // Calculate average z for color
      let z-avg = (p00.z + p01.z + p10.z + p11.z) / 4
      let color = color-func(0, 0, z-avg, 0, 1, 0, 1, z-lo, z-hi)
      
      // Draw two triangles
      line((p00.x, p00.y, p00.z), (p01.x, p01.y, p01.z), (p10.x, p10.y, p10.z), 
           close: true, fill: color, stroke: none)
      line((p01.x, p01.y, p01.z), (p11.x, p11.y, p11.z), (p10.x, p10.y, p10.z), 
           close: true, fill: color, stroke: none)
    }
  }
}

// Main Calabi-Yau visualization
#let calabi-yau(
  power: 3,
  angle: 0.5,
  subdivisions: 15,
  colormap: "jet",
  scale-factor: 3.0,
  rotation: (30deg, 45deg, 0deg),
  width: 400pt,
  height: 400pt,
) = {
  assert(power == int(power) and power > 0, message: "Power must be a positive integer")
  
  let n = power
  let alpha = angle
  let color-func = get-colormap(colormap)
  
  // Pre-compute all meshes and find global z bounds
  let all-meshes = ()
  let z-min = 1e10
  let z-max = -1e10
  
  for k1 in range(n) {
    for k2 in range(n) {
      let mesh = generate-branch-mesh(n, k1, k2, alpha, subdivisions)
      all-meshes.push(mesh)
      
      // Find z bounds
      for row in mesh {
        for point in row {
          z-min = calc.min(z-min, point.z)
          z-max = calc.max(z-max, point.z)
        }
      }
    }
  }
  
  // Create canvas and render all branches
  cetz.canvas(length: 1cm, {
    import cetz.draw: *
    
    // Set up 3D view
    scale(scale-factor)
    rotate(x: rotation.at(0), y: rotation.at(1), z: rotation.at(2))
    
    // Render all meshes
    for mesh in all-meshes {
      render-mesh(mesh, color-func, z-min, z-max)
    }
  })
}

