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

    /// Builds a mesh from the way DCC tools store one: shared vertex positions and, per triangle
    /// corner (3 per triangle, in `tri_vertices` order), a normal and a UV. Corners that share a
    /// vertex and have the same normal and UV become one vertex, so smooth shading welds and hard
    /// edges and UV seams split.
    pub fn from_corners(
        positions: &[[f32; 3]],
        tri_vertices: &[u32],
        normals: Option<&[[f32; 3]]>,
        uvs: Option<&[[f32; 2]]>,
    ) -> Result<Self, MeshError> {
        let corners = tri_vertices.len();
        let check = |attribute, actual: Option<usize>| match actual {
            Some(actual) if actual != corners => Err(MeshError::AttributeLength {
                attribute,
                expected: corners,
                actual,
            }),
            _ => Ok(()),
        };
        check("normals", normals.map(<[_]>::len))?;
        check("uvs", uvs.map(<[_]>::len))?;
        let mut seen = std::collections::HashMap::<(u32, [u32; 3], [u32; 2]), u32>::new();
        let (mut p, mut n, mut t) = (Vec::new(), Vec::new(), Vec::new());
        let mut indices = Vec::with_capacity(corners);
        for (c, &v) in tri_vertices.iter().enumerate() {
            let pos = *positions
                .get(v as usize)
                .ok_or(MeshError::IndexOutOfRange {
                    index: v,
                    vertices: positions.len(),
                })?;
            let (nc, uc) = (normals.map(|a| a[c]), uvs.map(|a| a[c]));
            let key = (
                v,
                nc.map_or([0; 3], |a| a.map(f32::to_bits)),
                uc.map_or([0; 2], |a| a.map(f32::to_bits)),
            );
            let next = p.len() as u32;
            indices.push(*seen.entry(key).or_insert_with(|| {
                p.push(pos);
                n.extend(nc);
                t.extend(uc);
                next
            }));
        }
        Self::new(p, normals.map(|_| n), uvs.map(|_| t), indices)
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
    fn from_corners_welds_equal_corners_and_splits_the_rest() {
        // Two triangles sharing the edge 1-2. Smooth normals on the shared edge weld; a different
        // normal at vertex 1 in the second triangle splits it.
        let pos = [[0.0; 3], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [1.0, 1.0, 0.0]];
        let up = [0.0, 0.0, 1.0];
        let tilt = [0.0, 0.6, 0.8];
        let m = Mesh::from_corners(&pos, &[0, 1, 2, 1, 3, 2], Some(&[up; 6]), None).unwrap();
        assert_eq!((m.positions().len(), m.indices().len()), (4, 6));
        let mut normals = [up; 6];
        normals[3] = tilt;
        let m = Mesh::from_corners(&pos, &[0, 1, 2, 1, 3, 2], Some(&normals), None).unwrap();
        assert_eq!(m.positions().len(), 5);
        let uv = [
            [0.0; 2],
            [1.0, 0.0],
            [0.0, 1.0],
            [1.0, 0.0],
            [1.0, 1.0],
            [0.0, 1.0],
        ];
        let m = Mesh::from_corners(&pos, &[0, 1, 2, 1, 3, 2], None, Some(&uv)).unwrap();
        assert_eq!((m.positions().len(), m.uvs().unwrap().len()), (4, 4));
        assert_eq!(
            Mesh::from_corners(&pos, &[0, 1, 9], None, None),
            Err(MeshError::IndexOutOfRange {
                index: 9,
                vertices: 4
            })
        );
        assert!(Mesh::from_corners(&pos, &[0, 1, 2], Some(&[up]), None).is_err());
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
