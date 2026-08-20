For an Azure SQL Database, both modes work well, but they behave very differently.

	Import	DirectQuery
Where data lives for reporting	Copied into Power BI	Remains in Azure SQL
Report speed	Usually much faster	Depends on SQL/query/network performance
Freshness	Data is as fresh as last refresh	Queries SQL when users interact
SQL workload	Mostly during refresh	Every report interaction can hit SQL
Power BI modeling	Most flexible	Some modeling/DAX limitations
Large datasets	Can hit model/capacity limits	Good when data is too large to import
Scheduled refresh	Required for new data	Generally not needed for data freshness
Import

With Import, Power BI effectively does this:

Azure SQL → copy data into Power BI → users query Power BI's in-memory model

So if your SQL table contains 10 million rows, Power BI loads the required data into its compressed in-memory model. When someone changes a slicer, Power BI generally answers from that model rather than going back to Azure SQL.

This usually gives the best report performance, and Microsoft recommends considering Import first unless you have a specific reason not to.

The downside is freshness. For example, if your refresh runs at:

08:00 → 12:00 → 16:00

then a database change at 09:00 may not appear until 12:00.

DirectQuery

DirectQuery is approximately:

User clicks slicer → Power BI generates SQL → Azure SQL executes query → results return to Power BI

The actual dataset isn't fully copied into Power BI. Microsoft confirms that interactions against DirectQuery models result in queries against the underlying source.

For example, a report visual may result in SQL conceptually similar to:

SELECT
    CustomerRegion,
    SUM(SalesAmount)
FROM Sales
WHERE OrderDate >= '2026-08-01'
GROUP BY CustomerRegion;

This means your report can reflect database changes very quickly.

But it also means Azure SQL becomes part of your report's performance path. If a SQL query takes 5 seconds, the Power BI visual may also take several seconds.

For Azure SQL specifically

I'd generally choose:

Import if:

your model fits comfortably in Power BI
refreshing every few hours/daily is acceptable
you want fast slicers and visuals
you have lots of measures/calculations
many users will use the report

DirectQuery if:

you genuinely need near-real-time data
the database is too large to reasonably import
governance requires the data to remain in Azure SQL
users normally query relatively small/filterable portions of a huge database

Microsoft's current guidance is essentially use Import by default and move to DirectQuery when latency, scale, governance, security, or architectural requirements justify it.

One important Azure SQL advantage: for a normal publicly accessible Azure SQL Database, DirectQuery from Power BI Service generally doesn't require an on-premises gateway. A gateway may be required if the database uses a private IP/private networking configuration.

What I would probably do in your situation

If your Azure SQL database is a typical business database—say sales, customers, orders, finance, operations—I'd start with:

Azure SQL → Power BI Import mode → star schema → scheduled/incremental refresh

rather than DirectQuery.

Even with tens or hundreds of millions of source rows, incremental refresh can often make Import practical, because Power BI doesn't need to reload the entire history every refresh. DirectQuery shouldn't automatically be chosen just because the SQL database is large.

There's also a third option: a composite/hybrid model, where you can keep historical data imported for speed while querying recent data with DirectQuery. Power BI supports mixing storage modes in these scenarios.

If you tell me roughly how many rows your largest SQL table has, how often the SQL data changes, and how fresh the Power BI report needs to be, I can tell you which mode I'd choose for your Azure SQL setup.

Yes — Azure SQL + DirectQuery is publishable.

One especially common issue is this:

If the report was previously published using Import

Suppose you originally had:

Azure SQL → Import → Power BI

and published Sales Report.

Then you changed the PBIX to:

Azure SQL → DirectQuery → Power BI

and tried to publish it again over the existing Sales Report semantic model.

Power BI does not support overwriting an existing Import semantic model with a DirectQuery/Live Connection version during republish. Microsoft's current publishing documentation explicitly lists that conversion as unsupported.

Try this:

In Power BI Desktop, save the DirectQuery version with a different name, for example Sales Report DQ.pbix.
Publish it as a new report/semantic model instead of replacing the existing Import one.
Once published, go to Power BI Service → Workspace → Semantic model → Settings → Data source credentials.
Sign in/configure the credentials for your Azure SQL Database.

For a normal public Azure SQL endpoint such as:

myserver.database.windows.net

you generally do not need an on-premises gateway. If your Azure SQL Database uses a private endpoint/private IP/VNet, then you do need an appropriate gateway configuration.

So if you're getting something like “Publishing failed” specifically when replacing an existing report, my first suspicion would be the Import → DirectQuery overwrite restriction.

If you paste the exact Power BI publishing error here, I can tell you exactly which issue it is.

what if the earilier published report was also using direct query 

If the earlier published version was also DirectQuery, then the Import → DirectQuery restriction I mentioned does not apply. You should normally be able to republish the PBIX and overwrite the existing report/semantic model. Microsoft says republishing replaces the existing semantic model with the updated one; the unsupported conversion specifically concerns certain storage-mode changes such as Import → DirectQuery.

So in your case, I’d check these next:

Same-name conflicts: if your workspace somehow contains two semantic models with the same name as the PBIX, publishing can fail. Microsoft explicitly calls this out.
Tenant setting blocking republish: admins can enable “Block republish and disable package refresh”, which prevents replacing an existing report/model.
Permissions: you may be able to publish new content but not replace the existing semantic model/report, depending on workspace role/ownership.
Model changed into a composite model: if the PBIX now DirectQueries another Power BI semantic model, tenant settings can block publication even though plain DirectQuery to Azure SQL is allowed.
PBIX/network publishing issue: Microsoft also lists unstable network connections and file-size-related issues among publishing failures.

Also, Azure SQL credentials/gateway are usually a post-publish issue, not something that should prevent the PBIX itself from publishing. For normal Azure SQL cloud connections, you configure credentials in the semantic model settings after publishing; a gateway is generally only required when Azure SQL is behind a private IP/private network.

A useful test is to rename the PBIX and publish it as a brand-new report to the same workspace.

If that succeeds, your DirectQuery connection is probably fine and the problem is specifically with overwriting the existing report/semantic model.

If you paste the exact error you get when you click Publish → Replace, I can narrow it down very quickly.

This is the error message I get 

The screenshot makes the issue much clearer. This is not a DirectQuery publishing limitation. Your report/semantic model is trying to connect to the data source using Workspace Identity, and Power BI can't use that identity.

The key part of the error says, essentially:

The model uses a data connection configured for Workspace Identity authentication, but the workspace has no identity, or the model owner doesn't have permission to use it.

Microsoft documents the same requirement: if a semantic model uses Workspace Identity, the workspace must actually have a Workspace Identity configured, and the model owner needs at least Contributor access to the workspace.

Easiest fix if you don't specifically need Workspace Identity

For a normal Azure SQL + DirectQuery setup, you can usually use your Azure/Entra credentials instead.

In Power BI Service, open the workspace and go to your Semantic model → Settings → Data source / Gateway and cloud connections. Find the Azure SQL connection and check what connection it is mapped to.

If it currently shows something like:

Authentication method: Workspace identity

change/recreate the cloud connection using OAuth2 / Organizational account / Microsoft Entra ID, depending on what your tenant exposes, and map the semantic model to that connection.

Azure SQL DirectQuery supports Microsoft Entra authentication, including SSO scenarios.

If your organisation intentionally wants Workspace Identity

Then your Power BI/Fabric admin needs to configure it properly:

Open the workspace.
Go to Workspace settings → Workspace identity.
Choose + Workspace identity.
Make sure you, as the semantic-model owner, are at least Contributor in that workspace.
The Workspace Identity itself also needs permission to connect to/read the Azure SQL database.

Only a workspace admin can create/manage the Workspace Identity.

The architecture would then be:

Power BI report → Semantic model → Workspace Identity → Azure SQL

rather than:

Power BI report → your personal Azure SQL credentials → Azure SQL

Why this may have suddenly started happening

If the old version was also DirectQuery, that actually fits this error. Your old published semantic model may have been mapped to a different cloud connection/authentication method, while the republished version is now mapped to a connection configured with Workspace Identity.

So I would check Semantic model → Settings → Gateway and cloud connections first. My suspicion is that you'll see a connection there using Workspace Identity.

If you send me a screenshot of that Gateway and cloud connections section, I can tell you exactly which setting to change.
