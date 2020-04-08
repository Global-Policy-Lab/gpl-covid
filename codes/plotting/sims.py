import xarray as xr
import matplotlib.pyplot as plt
import numpy as np
import warnings

def facet_hist(estimates, case_type, coef, **kwargs):
    true_vals = {
        "Intercept": "no_policy_growth_rate",
        "p1": "p1_effect",
        "p2": "p2_effect",
        "p3": "p3_effect"
    }
    g = xr.plot.FacetGrid(estimates.sel(case_type=case_type), **kwargs, sharex=True)
    
    def nowarn_hist(*args, **kwargs):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            return plt.hist(*args, **kwargs)
    g.map(nowarn_hist,coef)
    g.map(lambda x: plt.axvline(np.nanmean(x), color="r", linestyle="--", label="Mean estimate"),coef)
    for ax in g.axes.flat:
        ax.axvline(estimates.attrs[true_vals[coef]], color='k', label="True value")
    g.axes.flat[0].legend()
    g.set_xlabels("")
    g.set_titles("$\{coord}$ = {value}")
    g.fig.suptitle(f"LHS: {case_type}; variable: {coef}")
    return g