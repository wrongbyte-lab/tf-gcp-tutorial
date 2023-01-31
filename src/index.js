const myFunction = async (req, res) => {
    const name = req.query.name || "World";
    res.send(`Hello ${name}!`);
  };
  
  module.exports = {
      myFunction
  }
  