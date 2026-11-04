use std::fmt;

/// Indexed triangle mesh in object space.
#[derive(Clone, Debug, PartialEq)]
pub struct Mesh {
    positions: Vec<[f32; 3]>,
    normals: Option<Vec<[f32; 3]>>,
    uvs: Option<Vec<[f32; 2]>>,
    indices: Vec<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MeshError {
    /// Index count is zero or not a multiple of 3.
    BadIndexCount(usize),
    IndexOutOfRange {
        index: u32,
        vertices: usize,
    },
    /// Normals or UVs do not have one entry per position.
    AttributeLength {
        attribute: &'static str,
        expected: usize,
        actual: usize,
    },
}

impl fmt::Display for MeshError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::BadIndexCount(n) => write!(f, "index count {n} is not a non-zero multiple of 3"),
            Self::IndexOutOfRange { index, vertices } => {
                write!(f, "index {index} is out of range for {vertices} vertices")
            }
            Self::AttributeLength {
                attribute,
                expected,
                actual,
            } => {
                write!(f, "{attribute} has {actual} entries, expected {expected}")
            }
        }
    }
}

impl std::error::Error for MeshError {}

impl Mesh {
    pub fn new(
        positions: Vec<[f32; 3]>,
        normals: Option<Vec<[f32; 3]>>,
        uvs: Option<Vec<[f32; 2]>>,
        indices: Vec<u32>,
    ) -> Result<Self, MeshError> {
        if indices.is_empty() || !indices.len().is_multiple_of(3) {
            return Err(MeshError::BadIndexCount(indices.len()));
        }
        if let Some(&index) = indices.iter().find(|&&i| i as usize >= positions.len()) {
            return Err(MeshError::IndexOutOfRange {
                index,
                vertices: positions.len(),
            });
        }
        let expected = positions.len();
        let check = |attribute, actual: Option<usize>| match actual {
            Some(actual) if actual != expected => Err(MeshError::AttributeLength {
                attribute,
                expected,
                actual,
            }),
            _ => Ok(()),
        };
        check("normals", normals.as_ref().map(Vec::len))?;
        check("uvs", uvs.as_ref().map(Vec::len))?;
        Ok(Self {
            positions,
            normals,
            uvs,
            indices,
        })
    }

    pub fn positions(&self) -> &[[f32; 3]] {
        &self.positions
    }

    pub fn normals(&self) -> Option<&[[f32; 3]]> {
        self.normals.as_deref()
    }

    pub fn uvs(&self) -> Option<&[[f32; 2]]> {
        self.uvs.as_deref()
    }

    pub fn indices(&self) -> &[u32] {
        &self.indices
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TRI: [[f32; 3]; 3] = [[0.0; 3], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]];

    #[test]
    fn accepts_a_valid_triangle() {
        assert!(Mesh::new(TRI.to_vec(), None, None, vec![0, 1, 2]).is_ok());
    }

    #[test]
    fn rejects_bad_input() {
        let new = |n: Option<Vec<[f32; 3]>>, i: Vec<u32>| Mesh::new(TRI.to_vec(), n, None, i);
        assert_eq!(new(None, vec![]), Err(MeshError::BadIndexCount(0)));
        assert_eq!(new(None, vec![0, 1]), Err(MeshError::BadIndexCount(2)));
        assert_eq!(
            new(None, vec![0, 1, 3]),
            Err(MeshError::IndexOutOfRange {
                index: 3,
                vertices: 3
            })
        );
        assert_eq!(
            new(Some(vec![[0.0; 3]]), vec![0, 1, 2]),
            Err(MeshError::AttributeLength {
                attribute: "normals",
                expected: 3,
                actual: 1
            })
        );
    }
}
