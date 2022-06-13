const path = require('path');

module.exports = {
    entry: path.resolve(__dirname, 'src/index.js'),
    mode:"development",
    module: {
      rules: [
          {
              test: /\.js$/,
              exclude: /node_modules/,
              use: {
                  loader: "babel-loader"
              }
          }
      ]
    },
    output: {
        path: path.resolve(__dirname, "dist"),
        filename: 'index.js',
        library: {
            name: 'MWI_WebSocket',
            type: 'umd'
        }
    },
    devServer: {
        contentBase: path.join(__dirname, 'dist'),
        port: 9000,
        headers: {
            'Access-Control-Allow-Origin': '*'
        }
    }
};