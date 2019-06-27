# Meteoroid

Meteoroid is the HCA DCP Data Processing Service Infrastructure Test Suite; it runs fast and concurrently while being highly pluggable and CI/CD agnostic.

![Meteoroid Diagram](https://www.lucidchart.com/publicSegments/view/9fc9f961-169b-4d2e-bc37-2cff68744559/image.png)

## MVP

- [ ] It's able to run integration test on a CI/CD system.
- [ ] It's able to run integration test locally on a laptop.
- [ ] It's functionally equivalent to the existing integration test.
- [ ] It has a simple CLI.
- [ ] Its sub-components are loosely-coupled.

## Development

### Dependency Management
We use [Poetry](https://poetry.eustace.io/) to manage the Python dependencies. (_check [here](https://github.com/sdispater/poetry#why) about why using Poetry_) 

Follow the documentation to install Poetry, you will need to run something like: `curl -sSL https://raw.githubusercontent.com/sdispater/poetry/master/get-poetry.py | python3`. 

Once you have Poetry installed:
- use `poetry add $PACKAGE` to add a new dependency.
- use `poetry install` to install the dependencies based on the `poetry.lock` file.
- use `poetry -h` to print help messages.
- use `poetry install --develop DEVELOP` to install Meteoroid istelf for developemnt puerposes. (similar to `pip install -e .`)
