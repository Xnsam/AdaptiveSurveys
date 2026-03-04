## Chat analytics for early intervention as per Biopsychosocial Model


### Aim 

To identify mental health factors corresponding to biology, psychology and social factors from user conversations. The model to predict intervention is modelled on reddit mental health subreddit posts.

### Expected Outcome 

Prognostic model to detect user trajectory and recommend early intervention

### Expected Clinical Benefits

Tailoring of Treatment for preemptive measures / early interventions
Clarity of Diagnosis - root cause and factors associated to the mental state
Object Baseline - the starting point of the journey
Risk assessment - how bad the situation is right now 

### Execution Plan

Retrospective Analysis - Develop user journeys from the data, with subreddit transition times, and subreddits as states. 
Thematic analysis - Identify the themes / factors associated to each state in the user journeys
Prognostic predictive modelling 

### Idea

The idea is given a new user, predict the journey of the user and if the user is accelerating faster in states then the clinical intervention is produced given the probability of the path. The first subreddit is considered as the behaviour baseline. The subreddit journey is a graph with hours between each subreddit (defined as “a state” here) and weights (defined as transition time here). The transition between subreddits could be considered as acceleration. Slower the acceleration the better. 

Dataset used in the use case is Reddit Mental health dataset
https://www.kaggle.com/datasets/entenam/reddit-mental-health-dataset


More details:
[Detailed document](document.pdf)



