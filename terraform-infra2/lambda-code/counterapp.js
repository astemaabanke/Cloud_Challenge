/*
author: Alex Tema Abanke
email: atemaaba@terpmail.umd.edu
purpose: This file contains javascript code that will be used to run a Lambda Function that accepts HTTPs request from 
API gateway. These request will trigger the lambda function; the function will track visitor count on a webpage and save 
the count visit in a database (DynamoDb)

*/

// Import AWS software development kit that will be used to access various AWS resources 
const AWS = require('aws-sdk');

// make an instance of DynamoDB; this allows to send request to DynamoDB
const dynamodb = new AWS.DynamoDB.DocumentClient();

// the exports.handler is where request are passed in the aynchronous function 
exports.handler = async (event) => {

  // define what actions is doing to take place in the database
  const params = {
    TableName: 'VisitorCount2', // define which tablename to access in the created database
    Key: {id: 'counter2'}, // variables that track how many people visited the page in the database
    UpdateExpression: 'SET visitCount = if_not_exists(visitCount, :start) + :inc',  // counter will start from 0 and incremented by 1 

    ExpressionAttributeValues: {
      ':inc': 1, 
      ':start': 0
    },
    ReturnValues: 'UPDATED_NEW'

  };

  try {
    // the data variables will contain information about the updated operation from the database
    const data = await dynamodb.update(params).promise();
    return {
      statusCode: 200,
      body: JSON.stringify({ visitCount: data.Attributes.visitCount})
    };
  } catch(err){ // in the case that the operation fails
    return {
      statusCode: 500, 
      body: JSON.stringify({error: err.message})
    };
  }


};




