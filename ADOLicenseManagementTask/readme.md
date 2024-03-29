# Azure DevOps User License Management

#### Author - Aammir Mirza


[![Donate](images/Paypal.jpg)](https://www.paypal.me/aammirmirza/7)

Use to manage Azure DevOps License cost. For un-used licenses it changes the user entitlement to Stakeholder. As a best prectice in cost savings it reduces the cost for un-used licenses.

Extension takes a close look at the number of Visual Studio Team Services subscribers in the organization and make sure that entitles users actively using their license.

<span style="background-color: #83DFBE">With entitlemen changes _(Changing un-used Azure DevOps licences to STAKEHOLDER)_ the cost can be reduced for _Basic and Basic + Test_ user licenses.

You can run the task accross all the organization, based on number of days 'last used' or 'active status' within the days.</span>

## Platform

* Windows *Provides logs file features that can be artifact*
* Linux

## Installation

Download the Free _'Azure DevOps License Management Tasks'_ from here and populate the below mentioned mandatory parameters to get it working

Available task name after installation - 'ADO License Management'

## Configuration

### Classic Pipeline (UI)

* Generate PAT token for All accessible orgs. This token you will be using across all orgs for cost savings extension.

* Adding the extension using classic pipeline (UI-Based pipeline in AzDO)
-- Under Organization, mention the list of all organizations you want to run the cost savings for licenses.
-- NumberOfMonths check for all the users those who have not access the AzDO from # number of months
-- AccessToken pass token PAT that you have generated for all org, passing it as masked pipeline variable

* Skipping the check for service accounts or specific automation users can be achieved from advanced option within the task.

* Logs (csv) availble for artifact packaging as .CSV. Available output in pipeline artifact `(Limited feature for windows agent)`.

* [New Feature] Send email **notofication toggle** added with SMTP configuration, to notify actioned users. Also csv log has random prefix added so that it should not append to existing
csv file (in case of self-hosted agent)


#### Minimum required previlages for the token to perform the task

* Members Entitlement Management (Read & Write)


## Operation arguments

Available command line options are:

* **`Organizations`** Delimited list of organizations to perform cost savings for AzDO user licenses. E.g. Organization1,Organization2,Org3 etc.
* **`AccessToken`** Authentication token used in client auth. This token need to be generated for 'All Organization' in case of multiple organizations.
* **`NumberOfMonths`** Number of months for checking if user last logged-in.
* **`usersExcludedFromLicenseChange`** As a advanced feature you can mention delimited list of users email address that need to be excluded for removing paid licenses and making entitlement as Stakeholder.
* **`emailNotify`** When set to 'True', It will send eMail notification to all actioned user. Allows you to add email body content.
  * **`SMTP_UserName`** Username (email address) from where the will be send. It is the same as credential username for SMTP.
  * **`SMTP_Password`** Password for the SMTP username
  * **`sentFrom`** Address that shpuld be used to handle reply-to. Address should exist in Office365. If nothing provided SMTP_Username will be default.
  * **`adiitionalComment`** eMail message body additional to default mail content.
    * **`Default mail content`** Your license has been downgraded to STAKEHOLDER.

#### YAML Usage

```yaml
steps:
  - task: AammirMirza.CP-ADOLicenseManagementprivate.ADOLicenseManagement-Task.ADOLicenseManagement@1
    displayName: "ADO License Management"
    inputs:
      Organizations: "'Organization-Name1', 'Organization-Name2', 'Organization-Name3'"
      NumberOfMonths: 2
      AccessToken: "$(atokent)"
      usersExcludedFromLicenseChange: "'user1@email.com','user2@email.com','usern@email.com'" # Optional
      emailNotify: true # Optinal : new feature added, to send the email notification to the actioned user(s)
      SMTP_UserName: 'aammir.mirza@hotmail.com' # dependent attribute if 'emailNotify = True'
      SMTP_Password: '$(smtpPassword)' # dependent attribute if 'emailNotify = True'. Password for the senders mailbox.
      sentFrom: 'aammir.mirza@hotmail.com' # dependent attribute if 'emailNotify = True'. eMail address should exist.
      adiitionalComment: 'This has been disabled for user as the user has never connect from several months.' # dependent attribute if 'emailNotify = True'. Any additional comment that contributes to email body.

  # Below task added for packaging the generated log as build artifacts ONLY FOR WINDOWS BUILD AGENT
  - task: PublishBuildArtifacts@1
    displayName: 'Publish Artifact: completon_log'
    inputs:
      ArtifactName: 'completon_log'

```

## Azure DevOps License cost _(as of 07 Jan 2021)_

* Stakeholder - Free
* Basic - First five users free, then $6 per user
* Basic + Test Plans - $52 per user
* Visual Studio Subscriber - $45 - $250 a month

## Success story
Please focus on highlighted rows of image, other rows may look blurry
#### Before
![Before](images/NovCost.png)

#### After
![After](images/DecCost.png)

## GIF for reference

 Placeholder


## Required previlages for PAT

* Members Entitlement Management (Read & Write)

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.

## Limitation

* Cannot change licenses or extensions inherited through group rules.
* Organization admin cannot be downgraded to stakeholder license.

## Updates

#### v1.0.2

* `how to use, demo gif added to help page.
#### v1.0.49
* `Extension platform independent capability added. Know can be used for Windows / Linux / Mac

#### v1.123.1

* `Added feature for pipeline to provide .csv as log file with the list of users and action performed for them. After the task need to add Publish artifact task`(Limited feature for windows agent)`.

E.g:

| Organization   | Licensed               | UserEmail          | Remark                     |
| -------------- | ---------------------- | ------------------ | -------------------------- |
| myorganization | Stakeholder            | myemai@email.com   | _NeverLoggedIn             |
| myorganization | Stakeholder            | excluded@email.com | _Skipped                   |
| myorganization | Error_changing_license | orgadmin@email.com | _OrgAdminOrPermissionIssue |

* ` Feature added to consider all those users whome access granted bit they never logged-in even for the first time. Saving the license cost for such users as well.

#### v1.138.1

* Error has been FIXED for 'Copy-file'

```json
  Copy-Item : Cannot find path
  Copy-Item : Cannot find path
  'D:\a\_tasks\ADOLicenseManagement_4e779492-fcca-40f0-bf69-2b3a577b3ba5\1.134.1\ActionedUsersLog.csv' because it does not exist.

```

#### v1.169.1

New feature for email notification added, along with refinement/correction to the existing repeated record entries within the csv logs.

#### v1.178.1
Fixed script failure error
Fixed log file generation issue
Fixed skip logic for the Admins and exceptional users

Note: Some cases pipeline status fails (Manual error state), still will generate the csv log with details of failure user IDs.

#### v1.191.1
Added the feature to find all the accessible organization with the provided PAT. Now **`Organization`** variable is only needed when you want to run the optimization for the specific sets of AzDO Organizations. If It is left blank, it will run agains all the accesible organization from the PAT token.

## License

[MIT](https://choosealicense.com/licenses/mit/)

## Support

emailto: aammir.mirza@hotmail.com
