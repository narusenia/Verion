//! IES photometric profiles (LM-63) for point and spot lights (REQ-CORE-004).

use std::fmt;

/// Vertical samples (0..=180 degrees, one per degree) and horizontal samples (0..=360) of the
/// resampled table.
pub const VERTICAL: usize = 181;
pub const HORIZONTAL: usize = 361;

/// A candela distribution on a regular one-degree grid. `parse` scales it so its peak is 1 and keeps
/// the file's peak (candela times the file's multiplier) in `peak`; `scaled` multiplies the table to
/// make it an intensity factor. Row `h` holds the vertical angles 0..=180 at horizontal angle `h`
/// degrees. Vertical 0 points down the light's axis.
#[derive(Clone, Debug, PartialEq)]
pub struct IesProfile {
    table: Vec<f32>,
    peak: f32,
}

#[derive(Debug, PartialEq, Eq)]
pub enum IesError {
    Truncated,
    Number(String),
    /// Only photometric type C (vertical angle from the nadir) is supported.
    Photometric(u32),
    Empty,
}

impl fmt::Display for IesError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Truncated => write!(f, "the IES file ends early"),
            Self::Number(s) => write!(f, "the IES file has `{s}` where a number belongs"),
            Self::Photometric(t) => {
                write!(f, "photometric type {t} is not supported (only type C)")
            }
            Self::Empty => write!(f, "the IES file has no light"),
        }
    }
}

impl std::error::Error for IesError {}

impl IesProfile {
    /// The table, `HORIZONTAL` rows of `VERTICAL` values, row-major.
    pub fn table(&self) -> &[f32] {
        &self.table
    }

    /// The file's largest candela value, times its multiplier.
    pub fn peak(&self) -> f32 {
        self.peak
    }

    /// The profile with every table value multiplied by `factor`.
    pub fn scaled(mut self, factor: f32) -> Self {
        self.table.iter_mut().for_each(|v| *v *= factor);
        self
    }

    pub fn parse(text: &str) -> Result<Self, IesError> {
        let mut lines = text.lines();
        // Everything up to the TILT line is keywords.
        let tilt = lines
            .by_ref()
            .find_map(|l| l.trim().strip_prefix("TILT=").map(str::to_owned))
            .ok_or(IesError::Truncated)?;
        let rest: Vec<&str> = lines.collect();
        let mut tokens = rest
            .iter()
            .flat_map(|l| l.split(|c: char| c.is_whitespace() || c == ','))
            .filter(|t| !t.is_empty());
        let mut next = || -> Result<f64, IesError> {
            let t = tokens.next().ok_or(IesError::Truncated)?;
            t.parse().map_err(|_| IesError::Number(t.to_owned()))
        };
        if tilt.trim() == "INCLUDE" {
            next()?; // lamp-to-luminaire geometry
            let n = next()? as usize;
            for _ in 0..2 * n {
                next()?; // tilt angles and multipliers
            }
        }
        let _lamps = next()?;
        let _lumens = next()?;
        let multiplier = next()?;
        let nv = next()? as usize;
        let nh = next()? as usize;
        let photometric = next()? as u32;
        for _ in 0..7 {
            next()?; // units, luminous opening, ballast, version, watts
        }
        if photometric != 1 {
            return Err(IesError::Photometric(photometric));
        }
        if nv == 0 || nh == 0 {
            return Err(IesError::Empty);
        }
        let v: Vec<f64> = (0..nv).map(|_| next()).collect::<Result<_, _>>()?;
        let h: Vec<f64> = (0..nh).map(|_| next()).collect::<Result<_, _>>()?;
        let cd: Vec<f64> = (0..nv * nh)
            .map(|_| next().map(|c| c * multiplier))
            .collect::<Result<_, _>>()?;
        let peak = cd.iter().copied().fold(0.0, f64::max);
        if peak <= 0.0 {
            return Err(IesError::Empty);
        }
        // Linear interpolation over the vertical angles; zero outside the measured range.
        let vertical = |plane: usize, theta: f64| -> f64 {
            let row = &cd[plane * nv..(plane + 1) * nv];
            if theta < v[0] || theta > v[nv - 1] {
                return 0.0;
            }
            let i = v.partition_point(|&a| a <= theta).clamp(1, nv - 1);
            let t = if v[i] > v[i - 1] {
                (theta - v[i - 1]) / (v[i] - v[i - 1])
            } else {
                0.0
            };
            row[i - 1] + (row[i] - row[i - 1]) * t
        };
        // Horizontal planes, folded by the symmetry the file declares.
        let last = h[nh - 1];
        let fold = |phi: f64| -> f64 {
            if nh == 1 {
                0.0
            } else if last <= 90.0 {
                let p = if phi > 180.0 { 360.0 - phi } else { phi };
                if p > 90.0 { 180.0 - p } else { p }
            } else if last <= 180.0 {
                if phi > 180.0 { 360.0 - phi } else { phi }
            } else {
                phi
            }
        };
        let horizontal = |theta: f64, phi: f64| -> f64 {
            if nh == 1 {
                return vertical(0, theta);
            }
            let p = fold(phi).clamp(h[0], last);
            let i = h.partition_point(|&a| a <= p).clamp(1, nh - 1);
            let t = if h[i] > h[i - 1] {
                (p - h[i - 1]) / (h[i] - h[i - 1])
            } else {
                0.0
            };
            let (a, b) = (vertical(i - 1, theta), vertical(i, theta));
            a + (b - a) * t
        };
        let mut table = Vec::with_capacity(VERTICAL * HORIZONTAL);
        for ph in 0..HORIZONTAL {
            for th in 0..VERTICAL {
                table.push((horizontal(th as f64, ph as f64) / peak) as f32);
            }
        }
        Ok(Self {
            table,
            peak: peak as f32,
        })
    }

    /// The relative intensity (peak 1) at vertical angle `theta` and horizontal angle `phi`, both in
    /// degrees, with the bilinear filter the shaders use.
    pub fn at(&self, theta: f32, phi: f32) -> f32 {
        let th = theta.clamp(0.0, 180.0);
        let ph = phi.rem_euclid(360.0);
        let (i, j) = (th.floor() as usize, ph.floor() as usize);
        let (i1, j1) = ((i + 1).min(VERTICAL - 1), (j + 1).min(HORIZONTAL - 1));
        let (ft, fp) = (th - i as f32, ph - j as f32);
        let t = |j: usize, i: usize| self.table[j * VERTICAL + i];
        let a = t(j, i) * (1.0 - ft) + t(j, i1) * ft;
        let b = t(j1, i) * (1.0 - ft) + t(j1, i1) * ft;
        a * (1.0 - fp) + b * fp
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A downlight: full output at the nadir falling to zero at 90 degrees, one plane.
    const DOWNLIGHT: &str = "IESNA:LM-63-2002\n[TEST] x\nTILT=NONE\n1 1000 1 4 1 1 2 0 0 0\n1 1 10\n0 30 60 90\n0\n100 80 40 0\n";

    #[test]
    fn symmetric_downlight_is_normalized_and_round() {
        let p = IesProfile::parse(DOWNLIGHT).unwrap();
        assert_eq!(p.table().len(), VERTICAL * HORIZONTAL);
        assert!((p.at(0.0, 0.0) - 1.0).abs() < 1e-6);
        assert!(
            (p.at(30.0, 123.0) - 0.8).abs() < 1e-6,
            "one plane is the same all around"
        );
        assert!(
            (p.at(15.0, 0.0) - 0.9).abs() < 1e-6,
            "linear between samples"
        );
        assert_eq!(p.at(120.0, 0.0), 0.0, "nothing above the measured range");
        assert_eq!(p.peak(), 100.0);
        assert!((p.scaled(10.0).at(0.0, 0.0) - 10.0).abs() < 1e-5);
    }

    #[test]
    fn quadrant_symmetry_mirrors_the_planes() {
        // Planes at 0 and 90 degrees (a quadrant): 0 is brighter than 90.
        let s = "IESNA:LM-63-2002\nTILT=NONE\n1 1000 1 2 2 1 2 0 0 0\n1 1 10\n0 90\n0 90\n100 100 50 50\n";
        let p = IesProfile::parse(s).unwrap();
        assert!((p.at(45.0, 0.0) - 1.0).abs() < 1e-6);
        assert!((p.at(45.0, 90.0) - 0.5).abs() < 1e-6);
        assert!((p.at(45.0, 180.0) - 1.0).abs() < 1e-6, "mirrored to 0");
        assert!((p.at(45.0, 270.0) - 0.5).abs() < 1e-6, "mirrored to 90");
    }

    #[test]
    fn bad_files_are_errors() {
        assert_eq!(IesProfile::parse("nothing"), Err(IesError::Truncated));
        let a = DOWNLIGHT.replace("4 1 1 2", "4 1 2 2");
        assert_eq!(IesProfile::parse(&a), Err(IesError::Photometric(2)));
        assert!(matches!(
            IesProfile::parse(&DOWNLIGHT.replace("80", "x")),
            Err(IesError::Number(_))
        ));
        assert_eq!(
            IesProfile::parse(&DOWNLIGHT.replace("100 80 40 0", "0 0 0 0")),
            Err(IesError::Empty)
        );
    }
}
