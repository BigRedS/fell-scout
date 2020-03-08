$.getJSON( "api/teams/table", function(teams_table) { 
    console.log (teams_table)
    $("#tbl_teams").dataTable({
        "paging": false,
        "aaData": teams_table,
        "aoColumnsDefs": [
            {
                "sTitle": "Teams"
            },{
                "aTargets": [ 5 ],
                
                "mRender": function(date, type, full){
                    var expected_time = moment.local(date);
                    return expected_time.format("HH:MM")
                }    
            }
        ]
    })
})
