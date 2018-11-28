## Log and Monitor the Secondary-Analysis Service 

In order to monitor the service's status and respond to the incidents more efficiently, we need to properly:
- Log the events
- Create log-based metrics
- Create the health checks
- Integrate the health and metrics into centralized dashboard, e.g. Grafana.

HCA DCP provides a [centralized monitoring dashboard](https://github.com/HumanCellAtlas/dcp-monitoring) based on Grafana
for us to integrate to. 

The following instructions will walk through how to set up our service monitoring dashboards on DCP Grafana from the
Google Cloud perspective.


### 1. Grant permissions
- **Give permission to the Grafana Data Source**

    In order to let Grafana fetch data from the Google Cloud projects, you need to give the grafana service account
    `Monitoring Viewer` permissions to that Google Project. (_Note that the grafana service account should already exist 
    in another dcp google project and it just has to be given the right level of permissions to whichever project 
    you want to connect._) A typical Grafana service account email will look like: 
    `grafana-datasource@YYY.iam.gserviceaccount.com`, contact the DCP OPS team to get the specific account name. 
    In order to give it `Monitoring Viewer` permission, go to GCloud console and `ADD` the member through `IAM & admin`
    -> `IAM` section from the side bar.
    
- **Create service account key for editing the log-based metrics**

    Although it's feasible to create log-based metrics via the GCloud console, it's recommended to do it 
    programmatically using the provided script in this directory. In order to do that, you need to create a service
    account, for instance `dev-logging-manager@XXX.iam.gserviceaccount.com`, having `Project Editor` permission to the
    Google Project. You can go to GCloud console and `CREATE SERVICE ACCOUNT` the member through 
    `IAM & admin` -> `Service accounts` section from the side bar. Be sure to save the service account JSON key file 
    to somewhere safe and accessible. The path to this key file will be required by the script in section 2.


### 2. Check and create log-based metrics
- **Check the pre-defined metrics JSON**

    The `metrics_template.json` defined a list of useful log-based metrics for secondary-analysis service. It's possible 
    we need to extend it to add more metrics. the path to this JSON file will be required by the next step.
  
- **Create the log-based metrics in the Google Project**
    
    To use the helper script create log-based metrics, install the dependencies with `pip install -r requirements.txt`
    and then run the following commands:
    ```bash
    python create-metrics.py --service_account_path KEY_PATH --pre_defined_metrics_json METRICS_PATH --google_project PROJECT_NAME
    ```
    where:
    - `--service_account_path KEY_PATH` is the path to your service account JSON key that has `Project Editor`;
    - `--pre_defined_metrics_json METRICS_PATH` is the path to your pre-defined log-based metric JSON file; 
    - `--google_project PROJECT_NAME` is the name of your google project (optional, must match the project
    specified by the service account JSON key if provided);

Now you should be able to see the log-based metrics on the GCloud console through: `Logging` -> `Logs-based metrics` -> 
`User-defined Metrics` from the side bar.

### 3. Create the dashboards

Note: If this a vanilla set up, or you are adding more metrics to the dashboards, in order to template and update the 
dashboards on Grafana, you need to follow the complete instructions 
[here](https://github.com/HumanCellAtlas/dcp-monitoring). Otherwise if you already have the Grafana dashboards set up, 
once you update the log-based metrics, the changes should be reflected on the dashboards already.
