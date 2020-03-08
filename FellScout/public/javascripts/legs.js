$.getJSON( "api/legs/table", function(legs_table) { 
    console.log (legs_table)
    $("#tbl_legs").dataTable({
        "paging": false,
        "aaData": legs_table,
        "aoColumnsDefs": [
            {
                "sTitle": "legs"
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
