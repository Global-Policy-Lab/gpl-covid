import pandas as pd
import numpy as np
import os

from functools import reduce

raw_data_dir = '../../../data/raw/usa'
int_data_dir = '../../../data/interim/usa'
proc_data_dir = '../../../data/processed/adm1'

# rename the states
state_acronyms_to_names = \
{"all":"all",
 "AL":"Alabama",
 "AK":"Alaska",
 "AZ":"Arizona",
 "AR":"Arkansas",
 "AS":"American Samoa",
 "CA":"California",
 "CO":"Colorado",
 "CT":"Connecticut",
 "DE":"Delaware",
 "DC":"District of Columbia",
 "FL":"Florida",
 "GA":"Georgia",
 "GU":"Guam",
 "HI": "Hawaii",
 "ID":"Idaho",
 "IL":"Illinois",             
 "IN":"Indiana",              
 "IA":"Iowa",                 
 "KS":"Kansas" ,
 "KY":"Kentucky",
 "LA":"Louisiana",
 "ME":"Maine",
 "MD":"Maryland",
 "MA":"Massachusetts",
 "MI":"Michigan",
 "MN":"Minnesota",
 "MP":"Northern Marianas",
 "MS":"Mississippi",
 "MO":"Missouri",
 "MT":"Montana",
 "NE":"Nebraska",
 "NV":"Nevada"  ,            
 "NH":"New Hampshire",
 "NJ":"New Jersey"     ,
 "NM":"New Mexico",
 "NY":"New York",
 "NC":"North Carolina",
 "ND":"North Dakota",
 "OH":"Ohio",
 "OK":"Oklahoma",             
 "OR":"Oregon",
 "PA":"Pennsylvania",
 "PR": "Puerto Rico",
 "RI":"Rhode Island" ,
 "SC":"South Carolina",
 "SD":"South Dakota",
 "TN":"Tennessee",
 "TX":"Texas",
 "UT":"Utah",
 "VT":"Vermont",
 "VA":"Virginia",
 "VI":"Virgin Islands",
 "WA":"Washington",          
 "WV":"West Virginia",
 "WI":"Wisconsin",
 "WY":"Wyoming"   
}

def acc_to_statename(acc):
    return state_acronyms_to_names[acc]

def fix_date(date):
	month, day, year = date.split("/") 

	return "{y:04d}-{m:02d}-{d:02d}".format(y=2000+int(year), m=int(month), d=int(day))

def general_union(x):
    candidates =  reduce(np.union1d, x)
    
    if not hasattr(candidates, "__iter__"): #returns True if type of iterable - same problem with strings
        candidates = [candidates]
    
    return candidates

def min_no_nans(x):
    if not hasattr(x, "__iter__"): #returns True if type of iterable - same problem with strings
        return x
    else:
        sizes = []
        for size in x:
            if not np.isnan(size):
                sizes.append(size)
        if len(sizes) == 0:
            return np.nan
        else:
            return np.min(sizes)

def download_and_process_policy_csv():

	policy_data_raw = pd.read_csv(os.path.join(raw_data_dir,"US_COVID-19_policies.csv"),encoding='latin')

	# A. wrangle polices -> binary variables
	# get the unchanged vars
	policy_data = policy_data_raw.loc[:,['date', 'adm0_name', 'adm1_name', 'adm2_name']]
	
	policy_data.loc[:,'date'] = policy_data.loc[:,'date'].apply(fix_date)

	# fix the state names
	policy_data.loc[:,'adm1_name'] = policy_data['adm1_name'].apply(acc_to_statename)

	# Code all policies as 0/1
	policy_mandatory = policy_data_raw.loc[:,'Optional'] == 'N'
	policy_optional = policy_data_raw.loc[:,'Optional'] == 'Y'

	# 1. deal with school closures:
	school_closures_all = policy_data_raw.loc[:,'policy'] == 'school_closure'

	#np.logical_and(school_closures_all,policy_mandatory).astype(int)
	# add to data

	policy_data['school_closure']  = np.logical_and(school_closures_all,policy_mandatory).astype(int)
	policy_data['school_closure_opt'] = np.logical_and(school_closures_all,policy_optional).astype(int)

	# 2. deal with business closrues
	business_closures_all = policy_data_raw['policy'] == 'business_closure'

	# add to data
	policy_data['business_closure']  = np.logical_and(business_closures_all,policy_mandatory).astype(int)
	policy_data['business_closure_opt'] = np.logical_and(business_closures_all,policy_optional).astype(int)

	# 2. deal with no_gatherings
	no_gathering_all = policy_data_raw['policy'] == 'no_gathering'
	policy_data['no_gathering']  = np.logical_and(no_gathering_all,policy_mandatory).astype(int)
	policy_data['no_gathering_opt']  = np.logical_and(no_gathering_all,policy_optional).astype(int)
	policy_data['no_gathering_size']  = policy_data_raw['no_gathering_size'].copy()
	# make sure every gathering policy as a size associated
	policy_data.loc[policy_data['no_gathering']>0,'no_gathering_size'] = \
	            policy_data.loc[policy_data['no_gathering']>0,'no_gathering_size'].fillna(0)
	policy_data.loc[policy_data['no_gathering_opt']>0,'no_gathering_size'] = \
	            policy_data.loc[policy_data['no_gathering_opt']>0,'no_gathering_size'].fillna(0)
	# 3. Travel Ban
	# country
	travel_ban_all = policy_data_raw['policy'] == 'travel_ban_intl_out'
	policy_data['travel_ban_intl_out'] = travel_ban_all.astype(int)
	policy_data['travel_ban_intl_out_country_list'] = policy_data_raw['travel_ban_country_list'].copy()

	# local
	local_travel_ban_all = policy_data_raw['policy'] == 'travel_ban_local'
	policy_data['travel_ban_local'] = local_travel_ban_all.astype(int)

	# 4. Home isolation and social distance
	social_distance_all = policy_data_raw['policy'] == 'social_distance'
	policy_data['social_distance']  = np.logical_and(social_distance_all,policy_mandatory).astype(int)
	policy_data['social_distance_opt']  = np.logical_and(social_distance_all,policy_optional).astype(int)

	# 5. Libary closures 
	# delete b/c unused
	#policy_data['library_closure']= (policy_data_raw['policy'] == 'library_closure').astype(int)

	# 6. Work from home
	work_from_home_all = policy_data_raw['policy'] == 'work_from_home'
	policy_data['work_from_home']  = np.logical_and(work_from_home_all,policy_mandatory).astype(int)
	policy_data['work_from_home_opt']  = np.logical_and(work_from_home_all,policy_optional).astype(int)

	# 7. Event cancellations
	policy_data['event_cancel']= (policy_data_raw['policy'] == 'event_cancellation').astype(int)

	# 8. Free testing
	# delete b/c unused
#	policy_data['free_testing']= (policy_data_raw['policy'] == 'free_testing').astype(int)

	# 9. Home isolation
	home_isolation_all = policy_data_raw['policy'] == 'home_isolation'
	policy_data['home_isolation']  = np.logical_and(home_isolation_all,policy_mandatory).astype(int)
	policy_data['home_isolation_opt']  = np.logical_and(home_isolation_all,policy_optional).astype(int)

	# 10. Paid sick leave
	paid_sick_leave_all = policy_data_raw['policy'] == 'paid_sick_leave'
	policy_data['paid_sick_leave']  = np.logical_and(paid_sick_leave_all,policy_mandatory).astype(int)
	policy_data['paid_sick_leave_opt']  = np.logical_and(paid_sick_leave_all,policy_optional).astype(int)

	policy_data['adm1_pop_weight']  = policy_data_raw['adm1_pop_weight'].copy()

	# 10. emergency declaration
	policy_data['emergency_declaration'] = (policy_data_raw['policy'] == 'emergency_declaration').astype('int')

	# B. Weight each row accoridng to population weights
	admin_keys = ['date', 'adm0_name', 'adm1_name', 'adm2_name', 'adm1_pop_weight']
	policy_keys_nonbinary = ['travel_ban_intl_out_country_list', 'no_gathering_size']

	policy_keys = list(policy_data.keys())
	[policy_keys.remove(x) for x in admin_keys + policy_keys_nonbinary]

	for policy_key in policy_keys:
		weighted_policy_key = policy_key + "_popwt"
		policy_data[weighted_policy_key] = policy_data[policy_key] * policy_data_raw['adm1_pop_weight']

	# C. Merge by row
	policy_data_adm1_only = policy_data.drop('adm2_name', axis=1)
	policy_data_adm1_only['date_to_sort'] = pd.to_datetime(policy_data_adm1_only['date'])
	
	# aggregate rows differently for each column
	aggregation_styles = {}
	for policy_key in policy_keys:
	    aggregation_styles[policy_key] = 'max'
	    aggregation_styles[policy_key+"_popwt"] = 'max'
	    
	# shouldnt matter
	aggregation_styles['date_to_sort'] = 'max'
	# the functions general_union() and min_no_nans() are defined above
	aggregation_styles['travel_ban_intl_out_country_list'] = general_union
	aggregation_styles['no_gathering_size'] = min_no_nans

	df_rows_merged = policy_data_adm1_only.groupby(['date','adm0_name','adm1_name'], as_index=False).agg(aggregation_styles)
	
	# fix the travel ban countries list
	#df_rows_merged['travel_ban_intl_out_country_list'].map(lambda x: [i for i in x if not np.isnan(i)])

	formated_policy_data = df_rows_merged.sort_values(['date_to_sort','adm0_name','adm1_name']).drop(['date_to_sort'],axis=1)

	# save intermediate version
	formated_policy_data.to_csv(os.path.join(int_data_dir,"US_COVID-19_policies_reformatted.csv"),index=False)

	return df_rows_merged , policy_keys


def main():
	# download cases and policy data
	cases_data = pd.read_csv(os.path.join(int_data_dir,"usa_jhu_cases_state.csv"))
	# policy data
	df_rows_merged, policy_keys = download_and_process_policy_csv()
	policy_data_by_state = df_rows_merged.groupby('adm1_name')

	# testing regime data
	testing_regimes = pd.read_csv(os.path.join(int_data_dir,'usa_states_covidtrackingdotcom_int_with_testing_regimes.csv'))

	# add datetime to cases data for easy sorting
	cases_data.loc[:,'date_to_sort'] = pd.to_datetime(cases_data['date'])
	cases_data = cases_data.sort_values(['date_to_sort','adm1_name'])#.reset_index()

	num_cases_data = len(cases_data)
	# add all the columns we're gonna need
	policy_keys_popweighted = [x+"_popwt" for x in policy_keys]

	# add empty olumns
	for policy_key in policy_keys:
	    cases_data[policy_key] = np.zeros(num_cases_data)
	    
	for policy_key_popweighted in policy_keys_popweighted:
	    cases_data[policy_key_popweighted] = np.zeros(num_cases_data)

	cases_data['travel_ban_intl_out_country_list'] = [[] for i in range(num_cases_data)]

	# put it in for all
	policies_affecting_all_states = policy_data_by_state.get_group('all').reset_index(drop=True)
	len(policies_affecting_all_states)

	# fill in the policy columns for polices affecting all states
	for i in range(len(policies_affecting_all_states)):
	    this_policy = policies_affecting_all_states.loc[i]
	    
	    date_this_policy =this_policy['date_to_sort']
	    affected_case_rows = np.where(cases_data['date_to_sort'] >= date_this_policy)[0]

	    # policy keys
	    for policy_key in policy_keys:
	        cases_data.loc[affected_case_rows,policy_key] = np.maximum(cases_data.loc[affected_case_rows,policy_key].values,
	                                                                   this_policy[policy_key]) 
	    
	        # deal with travel countries [TODO]
	        if policy_key == 'travel_ban_intl_out':
	            
	            def add_countries(x):
	                return np.union1d(x,this_policy['travel_ban_intl_out_country_list'])
	            
	            cases_data.loc[affected_case_rows,'travel_ban_intl_out_country_list'] = cases_data.loc[affected_case_rows,'travel_ban_intl_out_country_list'].apply(add_countries)

	    # policy keys popweighted
	    for policy_key in policy_keys_popweighted:
	        frac_summed = cases_data.loc[affected_case_rows,policy_key].values + this_policy[policy_key]
	        cases_data.loc[affected_case_rows,policy_key] = np.minimum( frac_summed, 1.0)


	# now fill in the state specific policies
	cases_data_by_state = cases_data.groupby('adm1_name')

	state_names_with_polices = list(policy_data_by_state.groups.keys())
	if "all" in list(cases_data_by_state.groups.keys()):
	    state_names_with_polices.remove('all')

	# for each state
	for state in state_names_with_polices:
	    if not state in cases_data_by_state.groups.keys():
	        continue
	        
	    cases_this_state = cases_data_by_state.get_group(state).reset_index()

	    policies_this_state = policy_data_by_state.get_group(state).reset_index(drop=True)
	    
	    # for each state policy
	    for i in range(len(policies_this_state)):
	        this_policy = policies_this_state.loc[i]
	    
	        date_this_policy = this_policy['date_to_sort']
	    
	        # get idxs back into the original df
	        affected_case_rows = cases_this_state[cases_this_state['date_to_sort']>= date_this_policy]['index'].values
	        for policy_key in policy_keys:
	            cases_data.loc[affected_case_rows,policy_key] = np.maximum(cases_data.loc[affected_case_rows,policy_key].values,
	                                                                   this_policy[policy_key]) 
	            
	        for policy_key in policy_keys_popweighted:
	            frac_summed = cases_data.loc[affected_case_rows,policy_key].values + this_policy[policy_key]
	            cases_data.loc[affected_case_rows,policy_key] = np.minimum( frac_summed, 1.0)

	# 5. Merge in with covidtracking.com data for testing_regime
	# add a nan column to testing_regime
	cases_data.loc[:,'testing_regime'] = float("NaN")

	testing_regimes = testing_regimes[['date', 'adm1_name', 'testing_regime']].sort_values('date')
	testing_regimes.loc[:,'adm1_name'] = testing_regimes['adm1_name'].apply(acc_to_statename)
	testing_regimes_by_state = testing_regimes.groupby('adm1_name')

	for state in cases_data_by_state.groups.keys():
	    cases_this_state = cases_data_by_state.get_group(state).reset_index()
	    testing_regimes_this_state_all = testing_regimes_by_state.get_group(state)[['date','testing_regime']]
	    testing_regimes_this_state = pd.DataFrame(cases_this_state['date']).merge(testing_regimes_this_state_all,
	                                                                           how='left')

	    # first backfill anything
	    testing_regimes_this_state = testing_regimes_this_state.fillna(method='ffill')
	    # now fill any nans with 0
	    testing_regimes_this_state = testing_regimes_this_state.fillna(0)
	    
	    rows_this_state = cases_this_state['index'].values

	    # now add to cases_data
	    cases_data.loc[rows_this_state,'testing_regime'] = testing_regimes_this_state['testing_regime'].values

	

	#remove any unused ids
	unused_ids = ['travel_ban_intl_out_popwt', 'travel_ban_intl_out_country_list']
	cases_data_subset = cases_data.drop(['date_to_sort']+unused_ids,axis=1).reset_index(drop=True)

	for key in cases_data_subset.keys():
		if key == 'adm0_name':
			continue
		if len(np.unique(cases_data_subset[key])) == 1:
			cases_data_subset.drop([key], axis=1).reset_index(drop=True)

	# add in population 
	pops1 = pd.read_csv(os.path.join(int_data_dir.replace('usa','adm') , 'adm1/adm1.csv'), index_col = [0,1])
	cases_data_to_publish = cases_data_subset.join(pops1.loc['USA'].population,on='adm1_name', how='left')
	assert cases_data_to_publish.population.isnull().sum()==0, 'poplation is null'
    
    # publish
	cases_data_to_publish.to_csv(os.path.join(proc_data_dir,'USA_processed.csv'),index=False)


if __name__ == "__main__":
	main()
