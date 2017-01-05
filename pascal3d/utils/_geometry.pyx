import numpy as np
cimport numpy as np


DTYPE = np.float
ctypedef np.float_t DTYPE_t


def intersect3d_ray_triangle(
        np.ndarray[DTYPE_t, ndim=2] ray0,
        np.ndarray[DTYPE_t, ndim=2] ray1,
        np.ndarray[DTYPE_t, ndim=2] tri0,
        np.ndarray[DTYPE_t, ndim=2] tri1,
        np.ndarray[DTYPE_t, ndim=2] tri2,
        ):
    """
    Parameters
    ----------
    ray0, ray1: (N, 3) Ray vectors.
    tri0, tri1, tri2: (N, 3) Triangle vectors.

    Returns
    -------
    flags: :class:`numpy.ndarray` (N,)
        -1, 0, 1 or 2. 1 represents intersection.
    intersection: :class:`numpy.ndarray` (N, 3)
        Each intersection has (x, y, z) and np.nan as invalid value.
    """
    N = ray0.shape[0]

    flags = np.zeros((N,), dtype=np.int32)
    flags[...] = 1

    intersection = np.zeros((N, 3), dtype=np.float64)

    u = tri1 - tri0
    v = tri2 - tri0
    n = np.cross(u, v)
    invalid = (n == 0).sum(axis=-1) == 3
    flags[invalid] = -1
    intersection[invalid, ...] = np.nan

    ray_dir = ray1 - ray0
    w0 = ray0 - tri0
    a = - (n * w0).sum(axis=-1)
    b = (n * ray_dir).sum(axis=-1)
    invalid = np.abs(b) < 1e-6
    invalid_2 = np.bitwise_and(invalid, a == 0)
    flags[invalid_2] = 2
    intersection[invalid_2, ...] = np.nan
    invalid_0 = np.bitwise_and(invalid, a != 0)
    flags[invalid_0] = 0
    intersection[invalid_0, ...] = np.nan

    r = a / b
    invalid = r < 0
    flags[invalid] = 0
    intersection[invalid, ...] = np.nan

    # compute intersection point
    I = ray0 + r[:, np.newaxis].repeat(3, axis=-1) * ray_dir

    # compute inside/outside of plane
    uu = (u * u).sum(axis=-1)
    uv = (u * v).sum(axis=-1)
    vv = (v * v).sum(axis=-1)
    w = I - tri0
    wu = (w * u).sum(axis=-1)
    wv = (w * v).sum(axis=-1)
    D = uv * uv - uu * vv
    s = (uv * wv - vv * wu) / D
    invalid = np.bitwise_or(s < 0, s > 1)
    flags[invalid] = 0
    intersection[invalid] = I[invalid]
    t = (uv * wu - uu * wv) / D
    invalid = np.bitwise_or(t < 0, t > 1)
    flags[invalid] = 0
    intersection[invalid] = I[invalid]

    # set valid points
    intersection[flags == 1] = I[flags == 1]

    return flags, intersection


def raytrace_camera_frame_on_triangles(
        np.ndarray[DTYPE_t, ndim=1] pt_camera_origin,
        np.ndarray[DTYPE_t, ndim=2] pts_camera_frame,
        np.ndarray[DTYPE_t, ndim=2] pts_tri0,
        np.ndarray[DTYPE_t, ndim=2] pts_tri1,
        np.ndarray[DTYPE_t, ndim=2] pts_tri2,
        ):
    """Raytrace with camera model and triangles.

    Parameters
    ----------
    pts_camera_origin: :class:`numpy.ndarray` (3, )
        (x, y, z)
    pts_camera_frame: :class:`numpy.ndarray` (n_rays, 3)
        Each ray has (x, y, z) field.
    pts_tri0, pts_tri1, pts_tri2: :class:`numpy.ndarray` (n_triangles, 3)
        Points which define the triangle.

    Returns
    -------
    min_depth, max_depth: numpy.ndarray (n_rays,)
        Min/max, Depth value at each lay.
    """
    cdef unsigned int n_points = len(pts_camera_frame)
    cdef unsigned int n_triangles = len(pts_tri0)
    cdef np.ndarray[DTYPE_t, ndim=1] pt_camera_frame
    cdef np.ndarray[DTYPE_t, ndim=2] intersects
    cdef np.ndarray[DTYPE_t, ndim=1] intersects_z
    cdef np.ndarray[DTYPE_t, ndim=1] min_depth = np.zeros((n_points,), dtype=DTYPE)
    cdef np.ndarray[DTYPE_t, ndim=1] max_depth = np.zeros((n_points,), dtype=DTYPE)
    cdef DTYPE_t min_d, max_d
    for i_pt in range(n_points):
        pt_camera_frame = pts_camera_frame[i_pt]
        ray0 = np.repeat(pt_camera_origin[np.newaxis, :], n_triangles, axis=0)
        ray1 = np.repeat(pt_camera_frame[np.newaxis, :], n_triangles, axis=0)
        flags, intersects = intersect3d_ray_triangle(
            ray0, ray1, pts_tri0, pts_tri1, pts_tri2)
        intersects = intersects[flags == 1]
        if intersects.size == 0:
            min_d = max_d = np.nan
        else:
            intersects_z = np.abs(intersects[:, 2])
            argsort = np.argsort(intersects_z)
            min_d = intersects_z[argsort[0]]
            max_d = intersects_z[argsort[-1]]
        min_depth[i_pt] = min_d
        max_depth[i_pt] = max_d
    return min_depth, max_depth
