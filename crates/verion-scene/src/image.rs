use std::fmt;

/// Linear RGB float image, row-major from the top-left. Used for textures and environment maps.
#[derive(Clone, Debug, PartialEq)]
pub struct Image {
    width: u32,
    height: u32,
    pixels: Vec<[f32; 3]>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ImageError {
    Empty,
    PixelCount { expected: usize, actual: usize },
    NonFinite,
}

impl fmt::Display for ImageError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Empty => write!(f, "image size must be non-zero"),
            Self::PixelCount { expected, actual } => {
                write!(f, "image has {actual} pixels, expected {expected}")
            }
            Self::NonFinite => write!(f, "image contains NaN or infinite values"),
        }
    }
}

impl std::error::Error for ImageError {}

impl Image {
    pub fn new(width: u32, height: u32, pixels: Vec<[f32; 3]>) -> Result<Self, ImageError> {
        if width == 0 || height == 0 {
            return Err(ImageError::Empty);
        }
        let expected = width as usize * height as usize;
        if pixels.len() != expected {
            return Err(ImageError::PixelCount {
                expected,
                actual: pixels.len(),
            });
        }
        if pixels.iter().flatten().any(|v| !v.is_finite()) {
            return Err(ImageError::NonFinite);
        }
        Ok(Self {
            width,
            height,
            pixels,
        })
    }

    pub fn width(&self) -> u32 {
        self.width
    }

    pub fn height(&self) -> u32 {
        self.height
    }

    pub fn pixels(&self) -> &[[f32; 3]] {
        &self.pixels
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_size_count_and_values() {
        assert!(Image::new(2, 1, vec![[0.0; 3]; 2]).is_ok());
        assert_eq!(Image::new(0, 1, vec![]), Err(ImageError::Empty));
        assert_eq!(
            Image::new(2, 2, vec![[0.0; 3]; 3]),
            Err(ImageError::PixelCount {
                expected: 4,
                actual: 3
            })
        );
        assert_eq!(
            Image::new(1, 1, vec![[f32::NAN, 0.0, 0.0]]),
            Err(ImageError::NonFinite)
        );
    }
}
