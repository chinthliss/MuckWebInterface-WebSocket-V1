import * as url from 'url';
// const __filename = url.fileURLToPath(import.meta.url);
const __dirname = url.fileURLToPath(new URL('.', import.meta.url));

export default function config(args, options) {
    const isProduction = options.mode === "production";
    const isDevServer = process.argv.includes("serve");

    const appConfig = {
        entry: __dirname + '/src/index.js',
        mode: isProduction ? "production" : "development",
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
            path: __dirname + "dist/",
            filename: 'index.js',
            library: {
                name: 'MWI_WebSocket',
                type: 'umd'
            }
        }
    };

    const devServer = {
        contentBase: __dirname + 'dist/',
        port: 9000,
        headers: {
            'Access-Control-Allow-Origin': '*'
        }
    }

    return isDevServer ? { ...appConfig, devServer } : appConfig;
}

