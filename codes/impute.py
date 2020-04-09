import numpy as np

# ### Impute values in cases where cumulative counts rise and then fall
def convert_non_monotonic_to_nan(array):
    """Converts a numpy array to a monotonically increasing one.
    Args:
        array (numpy.ndarray [N,]): input array
    Returns:
        numpy.ndarray [N,]: some values marked as missing, all non-missing
            values should be monotonically increasing
    Usage:
        >>> convert_non_monotonic_to_nan(np.array([0, 0, 5, 3, 4, 6, 3, 7, 6, 7, 8]))
        np.array([ 0.,  0., np.nan,  3., np.nan, np.nan,  3., np.nan,  6.,  7.,  8.])
    """
    keep = np.arange(0, len(array))
    is_monotonic = False
    while not is_monotonic:
        is_monotonic_array = np.hstack(
            (array[keep][1:] >= array[keep][:-1], np.array(True))
        )
        is_monotonic = is_monotonic_array.all()
        keep = keep[is_monotonic_array]
    out_array = np.full_like(array.astype(np.float), np.nan)
    out_array[keep] = array[keep]
    return out_array


def log_interpolate(array):
    """Interpolates assuming log growth.
    Args:
        array (numpy.ndarray [N,]): input array with missing values
    Returns:
        numpy.ndarray [N,]: all missing values will be filled
    Usage:
        >>> log_interpolate(np.array([0, np.nan, 2, np.nan, 4, 6, np.nan, 7, 8]))
        np.array([0, 0, 2, 3, 4, 6, 7, 7, 8])
    """
    idx = np.arange(0, len(array))
    log_array = np.log(array.astype(np.float32) + 1e-1)
    interp_array = np.interp(
        x=idx, xp=idx[~np.isnan(array)], fp=log_array[~np.isnan(array)]
    )
    return np.round(np.exp(interp_array)).astype(np.int32)


def impute_cumulative_df(df, src_col, dst_col, groupby_col):
    """Calculates imputed columns and returns 
    Args:
        df (pandas.DataFrame): input DataFrame with a cumulative column
        src_col (str): name of cumulative column to impute
        dst_col (str): name of imputed cumulative column
        groupby_col (str): name of column containing names of administrative units,
            values should correspond to groups whose values should be accumulating
    Returns:
        pandas.DataFrame: a copy of `df` with a newly imputed column specified by `dst_col`
    Usage:
        >>> impute_cumulative_df(pandas.DataFrame([[0, 'a'], [5, 'b'], [3, 'a'], [2, 'a'], [6, 'b']]), 0, 1)
        pandas.DataFrame([[0, 'a', 0], [5, 'b', 5], [3, 'a', 0], [2, 'a', 2], [6, 'b', 6]], columns=[0, 1, 'imputed'])
    """
    if dst_col not in df.columns:
        df[dst_col] = -1

    for adm_name in df[groupby_col].unique():
        sub = df.loc[df[groupby_col] == adm_name].copy()

        # Set rising-then-falling cumulative counts to null in the original column
        sub.loc[sub[src_col].notnull(), src_col] = convert_non_monotonic_to_nan(
            np.array(sub.loc[sub[src_col].notnull(), src_col])
        )

        sub[dst_col] = log_interpolate(sub[src_col])

        df.loc[df[groupby_col] == adm_name] = sub

    return df
