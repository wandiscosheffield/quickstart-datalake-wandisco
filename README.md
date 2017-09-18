# quickstart-datalake-wandisco
## Hybrid Data Lake on the AWS Cloud


This Quick Start automatically deploys a hybrid environment that integrates on-premises Hadoop clusters with a data lake on the Amazon Web Services (AWS) Cloud. The deployment includes WANdisco Fusion, Amazon Simple Storage Service (Amazon S3), and Amazon Athena, and supports cloud migration and burst-out processing scenarios.

The Quick Start provides the option to deploy a Docker container, which represents your on-premises Hadoop cluster for demonstration purposes, and helps you gain hands-on experience with the hybrid data lake architecture. WANdisco Fusion replicates data from Docker to Amazon S3 continuously, ensuring strong consistency between data residing on premises and data in the cloud. You can use Amazon Athena to analyze and view the data that has been replicated.

This Quick Start deploys the data lake into a virtual private cloud (VPC) that spans two Availability Zones in your AWS account. The deployment and configuration tasks are automated by AWS CloudFormation templates that you can customize during launch.

The Quick Start offers two deployment options:

- Deploying the data lake into a new virtual private cloud (VPC) on AWS
- Deploying the data lake into an existing VPC on AWS

You can also use the AWS CloudFormation templates as a starting point for your own implementation.

![Quick Start architecture for a hybrid data lake on AWS](https://d0.awsstatic.com/partner-network/QuickStart/datasheets/wandisco-on-aws-architecture.png.png)

For architectural details, best practices, step-by-step instructions, and customization options, see the [deployment guide](https://s3.amazonaws.com/quickstart-reference/datalake/wandisco/latest/doc/hybrid-data-lake-with-wandisco-fusion.pdf).

To post feedback, submit feature ideas, or report bugs, use the **Issues** section of this GitHub repo.
If you'd like to submit code for this Quick Start, please review the [AWS Quick Start Contributor's Kit](https://aws-quickstart.github.io/). 
