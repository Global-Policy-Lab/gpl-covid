import pandas as pd
import os

import codes.utils as cutil
import codes.merge as merge

raw_data_dir = str(cutil.DATA_RAW / 'usa')
int_data_dir = str(cutil.DATA_INTERIM / 'usa')
proc_data_dir = str(cutil.DATA_PROCESSED / 'adm1')

output_csv_name = 'USA_processed_tmp.csv'

def main():

	cases_data = pd.read_csv(os.path.join(int_data_dir,"usa_usafacts_state.csv"))


	policy_data = pd.read_csv(os.path.join(raw_data_dir,"usa_policy_data.csv"),encoding='latin')

	policy_data = policy_data.rename(columns={'Optional': 'optional'})
	policy_data = policy_data.rename(columns={'date': 'date_start'})

	policy_data.loc[:,'date_start'] = pd.to_datetime(policy_data['date_start'])
	policy_data['date_end'] = pd.to_datetime('2099-12-31')

	df_merged = merge.assign_policies_to_panel(cases_data, policy_data, 1, errors='warn')

	# todo add testing regime

	# publish
	print('writing merged policy and cases data to ', os.path.join(proc_data_dir, output_csv_name))
	df_merged.to_csv(os.path.join(proc_data_dir, output_csv_name),index=False)

if __name__ == "__main__":
	main()