# Quota and workflow monitoring

This directory contains scripts for logging running workflows in Cromwell and quota usage in a Google Cloud Platform project.

## Setup

1. Create a VM to run the scripts
```
gcloud compute instances create monitor --scopes=default,compute-ro --zone=us-central1-b
```

2. Log into the VM
```
gcloud compute --project broad-dsde-mint-staging ssh --zone us-central1-b monitor
```

3. Switch to root
```
sudo bash
```

4. Install git
```
apt-get install git
```

5. Clone repo onto VM
```
cd /usr/local/lib
git clone https://github.com/HumanCellAtlas/secondary-analysis.git
```

6. Copy files
```
cd secondary-analysis/monitor
cp *.py *.sh /usr/local/bin
cp quotas.log workflows.log /var/log
```

7. Create cron job
```
crontab -e
```
If prompted, choose your preferred editor.
Then, in the editor, paste this line at the end:
```
0,5,10,15,20,25,30,35,40,45,50,55 * * * * bash /usr/local/bin/check_quotas.sh
0,5,10,15,20,25,30,35,40,45,50,55 * * * * bash /usr/local/bin/check_workflows.sh dev /etc/cromwell/creds.json >> /var/log/workflows.log
```

This will write quota usage to /var/log/quotas.log and running workflow counts to /var/log/workflows.log every five minutes.
